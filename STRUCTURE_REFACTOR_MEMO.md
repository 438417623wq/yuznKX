# Structure Refactor Memo

Updated: 2026-02-25

## Scope and Constraint
- Refactor type: structure only.
- Must keep behavior unchanged:
  - business logic
  - algorithms
  - API/provider contracts
  - data models and parameter semantics

## What Was Reorganized

### 1) Storage Management (Settings)
Original entry file:
- `lib/features/settings/presentation/screens/storage_management_screen.dart`

Current structure:
- `lib/features/settings/presentation/screens/storage_management_screen.dart`
- `lib/features/settings/presentation/screens/storage_management/storage_management_data_extension.dart`
- `lib/features/settings/presentation/screens/storage_management/storage_management_actions_extension.dart`
- `lib/features/settings/presentation/screens/storage_management/storage_management_ui_extension.dart`
- `lib/features/settings/presentation/screens/storage_management/storage_management_models.dart`

Responsibilities:
- `storage_management_data_extension.dart`: usage scan and size calculation
- `storage_management_actions_extension.dart`: clear/backup/import/refresh actions
- `storage_management_ui_extension.dart`: summary cards, action buttons, section UI
- `storage_management_models.dart`: local section/stat models

### 2) Preset Edit (Presets)
Original entry file:
- `lib/features/presets/presentation/screens/preset_edit_screen.dart`

Current structure:
- `lib/features/presets/presentation/screens/preset_edit_screen.dart`
- `lib/features/presets/presentation/screens/preset_edit/preset_edit_parameters_extension.dart`
- `lib/features/presets/presentation/screens/preset_edit/preset_edit_function_extension.dart`
- `lib/features/presets/presentation/screens/preset_edit/preset_edit_prompts_extension.dart`
- `lib/features/presets/presentation/screens/preset_edit/preset_edit_regex_extension.dart`

Responsibilities:
- `preset_edit_parameters_extension.dart`: parameter tab + slider helpers
- `preset_edit_function_extension.dart`: function tab UI
- `preset_edit_prompts_extension.dart`: prompt list + prompt item UI
- `preset_edit_regex_extension.dart`: regex list/filter/update UI

## Validation
- `flutter analyze` completed without new hard errors from this refactor.
- `flutter test` passed for existing automated tests.

## Notes
- Some UI strings were normalized during split to avoid terminal encoding corruption.
- If needed, UI copy can be localized/restored in a dedicated text pass without touching logic.

## Next Candidates (Optional)
1. `lib/features/chat/data/chat_provider.dart`
2. `lib/features/presets/domain/models/preset.dart`
3. `lib/features/character/presentation/screens/character_edit_screen.dart`
