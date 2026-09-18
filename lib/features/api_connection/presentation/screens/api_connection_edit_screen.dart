import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/api_connection_provider.dart';
import '../../domain/models/api_connection.dart';
import '../../../chat/data/transport/local_chat_template.dart';

class ApiConnectionEditScreen extends ConsumerStatefulWidget {
  final ApiConnection? connection;

  const ApiConnectionEditScreen({super.key, this.connection});

  @override
  ConsumerState<ApiConnectionEditScreen> createState() => _ApiConnectionEditScreenState();
}

class _ApiConnectionEditScreenState extends ConsumerState<ApiConnectionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  
  ApiPlatform _selectedPlatform = ApiPlatform.customOpenAi;
  String? _localModelPath;
  bool _isTesting = false;

  // Local optimization settings
  double _nThreads = 4;
  double _nBatch = 512;
  double _nContext = 8192;
  bool _flashAttn = false;
  LocalChatTemplate _chatTemplate = LocalChatTemplate.auto;

  // Remote settings
  final TextEditingController _contextSizeController = TextEditingController();
  bool _includeUsage = true;

  static int? _readInt(dynamic raw) {
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  static double _readDouble(dynamic raw, double fallback) {
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is String) {
      return double.tryParse(raw.trim()) ?? fallback;
    }
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    final c = widget.connection;
    _nameController = TextEditingController(text: c?.name ?? 'New API');
    _baseUrlController = TextEditingController(text: c?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: c?.apiKey ?? '');
    _modelController = TextEditingController(text: c?.model ?? 'gpt-3.5-turbo');
    _localModelPath = c?.localModelPath;
    
    if (c != null) {
      try {
        _selectedPlatform = ApiPlatform.values.firstWhere((e) => e.label == c.platform);
      } catch (_) {
        _selectedPlatform = ApiPlatform.customOpenAi;
      }
      
      // Load params
      _nThreads = _readDouble(c.parameters['n_threads'], 4);
      _nBatch = _readDouble(c.parameters['n_batch'], 512);
      // 默认 8192：2048 会让世界书预算（25%）只剩 512 token，绝大多数
      // 角色卡内嵌世界书都挤不进去，表现为「设定没读取」。
      _nContext = _readDouble(c.parameters['context_size'], 8192);
      _flashAttn = c.parameters['flash_attn'] == true;
      _includeUsage = c.parameters['include_usage'] != false;
      _chatTemplate = LocalChatTemplate.fromId(
        c.parameters['chat_template']?.toString(),
      );

      final remoteContextSize = _readInt(c.parameters['context_size']);
      if (remoteContextSize != null && remoteContextSize > 0) {
        _contextSizeController.text = remoteContextSize.toString();
      }
    }
  }

  @override
  void dispose() {
    _contextSizeController.dispose();
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any, // GGUF usually doesn't have a standard mime type
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (path.toLowerCase().endsWith('.gguf')) {
        setState(() {
          _localModelPath = path;
          // Auto-fill name if empty
          if (_nameController.text == 'New API') {
            _nameController.text = result.files.single.name;
          }
        });
      } else {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择 .gguf 格式的模型文件')));
        }
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入 API 地址')));
      setState(() => _isTesting = false);
      return;
    }

    try {
      final dio = Dio();
      final url = baseUrl.endsWith('/') ? '${baseUrl}models' : '$baseUrl/models';
      
      final response = await dio.get(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('连接成功！获取模型列表中...')));
          
          final data = response.data;
          List<String> models = [];
          if (data['data'] is List) {
            models = (data['data'] as List)
                .map((e) => e['id'] as String)
                .toList();
          }

          if (models.isNotEmpty) {
            _showModelSelectionDialog(models);
          } else {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('连接成功，但未找到可用模型')));
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接失败: ${response.statusCode}')));
        }
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('错误: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  void _showModelSelectionDialog(List<String> models) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('选择模型', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: models.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(models[index]),
                    onTap: () {
                      setState(() {
                        _modelController.text = models[index];
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _save() {
    if (_selectedPlatform != ApiPlatform.local && !_formKey.currentState!.validate()) return;

    if (_selectedPlatform == ApiPlatform.local && _localModelPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择本地模型文件')));
      return;
    }

    // 合并而非覆盖：编辑连接时不再丢掉已有参数。
    final Map<String, dynamic> params = Map<String, dynamic>.from(
      widget.connection?.parameters ?? const <String, dynamic>{},
    );

    if (_selectedPlatform == ApiPlatform.local) {
      params['n_threads'] = _nThreads;
      params['n_batch'] = _nBatch;
      params['context_size'] = _nContext;
      params['flash_attn'] = _flashAttn;
      params['chat_template'] = _chatTemplate.id;
      params.remove('include_usage');
    } else {
      params.remove('n_threads');
      params.remove('n_batch');
      params.remove('flash_attn');
      params.remove('chat_template');

      final contextSize = int.tryParse(_contextSizeController.text.trim());
      if (contextSize != null && contextSize > 0) {
        params['context_size'] = contextSize;
      } else {
        params.remove('context_size');
      }
      params['include_usage'] = _includeUsage;
    }

    final newConnection = widget.connection?.copyWith(
      name: _nameController.text,
      platform: _selectedPlatform.label,
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
      model: _modelController.text,
      localModelPath: _localModelPath,
      parameters: params,
    ) ??
        ApiConnection.create(
          name: _nameController.text,
          platform: _selectedPlatform.label,
          baseUrl: _baseUrlController.text,
          apiKey: _apiKeyController.text,
          model: _modelController.text,
          localModelPath: _localModelPath,
        ).copyWith(parameters: params);

    ref.read(apiConnectionsProvider.notifier).saveConnection(newConnection);

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.connection == null ? '新建 API 连接' : '编辑 API 连接'),
        actions: [
           if (widget.connection != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                ref.read(apiConnectionsProvider.notifier).deleteConnection(widget.connection!.id);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ApiPlatform>(
                value: _selectedPlatform,
                decoration: const InputDecoration(labelText: '模型平台', border: OutlineInputBorder()),
                items: ApiPlatform.values.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p.label));
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedPlatform = val!;
                    if (_baseUrlController.text.isEmpty) {
                      _baseUrlController.text = val.defaultBaseUrl;
                    }
                  });
                },
              ),
              const SizedBox(height: 16),

              if (_selectedPlatform == ApiPlatform.local) ...[
                 Card(
                   color: Colors.white10,
                   child: Padding(
                     padding: const EdgeInsets.all(12.0),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         const Text('本地模型优化设置', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                         const SizedBox(height: 10),
                         
                         // Model Path
                         const Text('模型路径 (GGUF)', style: TextStyle(color: Colors.grey)),
                         const SizedBox(height: 4),
                         Row(
                           children: [
                             Expanded(
                               child: Text(
                                 _localModelPath ?? '未选择文件',
                                 style: const TextStyle(color: Colors.white70),
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ),
                             ElevatedButton(
                               onPressed: _pickLocalModel,
                               child: const Text('选择文件'),
                             ),
                           ],
                         ),
                         const Divider(color: Colors.white24),
                         
                         // Threads
                         Text('CPU 线程数: ${_nThreads.toInt()}', style: const TextStyle(color: Colors.white)),
                         Slider(
                           value: _nThreads,
                           min: 1,
                           max: 16,
                           divisions: 15,
                           label: _nThreads.toInt().toString(),
                           onChanged: (v) => setState(() => _nThreads = v),
                         ),
                         
                         // Context Size
                         Text('上下文长度 (Context): ${_nContext.toInt()}', style: const TextStyle(color: Colors.white)),
                         Slider(
                           value: _nContext,
                           min: 512,
                           max: 8192,
                           divisions: 15,
                           label: _nContext.toInt().toString(),
                           onChanged: (v) => setState(() => _nContext = v),
                         ),
                         
                         // Batch Size
                         Text('批处理大小 (Batch): ${_nBatch.toInt()}', style: const TextStyle(color: Colors.white)),
                         Slider(
                           value: _nBatch,
                           min: 128,
                           max: 2048,
                           divisions: 15,
                           label: _nBatch.toInt().toString(),
                           onChanged: (v) => setState(() => _nBatch = v),
                         ),

                         // Flash Attention
                         SwitchListTile(
                           title: const Text('Flash Attention (实验性)', style: TextStyle(color: Colors.white)),
                           subtitle: const Text('可能提高速度，但部分设备不支持', style: TextStyle(color: Colors.grey, fontSize: 12)),
                           value: _flashAttn,
                           onChanged: (v) => setState(() => _flashAttn = v),
                         ),

                         const Divider(color: Colors.white24),

                         // Chat Template
                         const Text('对话模板 (Chat Template)', style: TextStyle(color: Colors.white)),
                         const SizedBox(height: 6),
                         Container(
                           padding: const EdgeInsets.symmetric(horizontal: 10),
                           decoration: BoxDecoration(
                             border: Border.all(color: Colors.white24),
                             borderRadius: BorderRadius.circular(6),
                           ),
                           child: DropdownButton<LocalChatTemplate>(
                             value: _chatTemplate,
                             isExpanded: true,
                             dropdownColor: const Color(0xFF222130),
                             underline: const SizedBox.shrink(),
                             items: LocalChatTemplate.values
                                 .map((template) => DropdownMenuItem(
                                       value: template,
                                       child: Text(
                                         template.label,
                                         style: const TextStyle(
                                             color: Colors.white, fontSize: 13),
                                       ),
                                     ))
                                 .toList(),
                             onChanged: (value) => setState(() =>
                                 _chatTemplate =
                                     value ?? LocalChatTemplate.auto),
                           ),
                         ),
                         const SizedBox(height: 6),
                         const Text(
                           '自动识别会按模型文件名推断（Qwen / Llama 3 / Gemma / Mistral 等），'
                           '选错会明显影响输出质量。',
                           style: TextStyle(color: Colors.grey, fontSize: 12),
                         ),
                       ],
                     ),
                   ),
                 ),
              ] else ...[
                TextFormField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'API 接口地址', 
                    border: OutlineInputBorder(),
                    hintText: 'https://api.openai.com/v1'
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(labelText: 'API 密钥', border: OutlineInputBorder()),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _modelController,
                        decoration: const InputDecoration(labelText: '模型名称', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isTesting ? null : _testConnection,
                      child: _isTesting 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Text('测试/获取'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contextSizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '上下文窗口 (Context Size，可选)',
                    hintText: '留空则按协议默认：OpenAI 兼容 8192 / Claude 200000 / Gemini 32768',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('回读 token 用量 (stream_options.include_usage)'),
                  subtitle: const Text('若服务端不识别该字段会自动回退重试一次'),
                  value: _includeUsage,
                  onChanged: (v) => setState(() => _includeUsage = v),
                ),
              ],
              
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.indigoAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('保存', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
