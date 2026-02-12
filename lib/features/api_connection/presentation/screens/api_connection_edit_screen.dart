import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../data/api_connection_provider.dart';
import '../../domain/models/api_connection.dart';

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
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final c = widget.connection;
    _nameController = TextEditingController(text: c?.name ?? 'New API');
    _baseUrlController = TextEditingController(text: c?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: c?.apiKey ?? '');
    _modelController = TextEditingController(text: c?.model ?? 'gpt-3.5-turbo');
    
    if (c != null) {
      try {
        _selectedPlatform = ApiPlatform.values.firstWhere((e) => e.label == c.platform);
      } catch (_) {
        _selectedPlatform = ApiPlatform.customOpenAi;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
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
    if (!_formKey.currentState!.validate()) return;

    final newConnection = widget.connection?.copyWith(
      name: _nameController.text,
      platform: _selectedPlatform.label,
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
      model: _modelController.text,
    ) ?? ApiConnection.create(
      name: _nameController.text,
      platform: _selectedPlatform.label,
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
      model: _modelController.text,
    );

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
