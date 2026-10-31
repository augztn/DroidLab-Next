# DroidLab

DroidLab is a native desktop engineering workstation for Android firmware inspection, payload extraction, ADB diagnostics and guarded Fastboot operations.

**Migration status:** Flutter desktop rewrite in progress on `rewrite/flutter-desktop`. The original Python/Tkinter implementation remains preserved in [DroidLab-Next](https://github.com/augztn/DroidLab-Next) as the behavior and test reference.

## Current baseline

The first commit establishes the migration architecture and parity/safety documents. The Flutter foundation is being introduced as a modular workspace:
- `apps/desktop`: Flutter desktop app and composition root.
- `packages/droidlab_domain`: platform-independent models and contracts.
- `packages/droidlab_application`: routing and use-case orchestration.
- `packages/droidlab_backend_bridge`: managed Python JSONL subprocess bridge.
- `packages/droidlab_design_system`: Material 3 theme tokens/components.
- `backend/python`: existing Python workflows retained during migration.

See [Architecture](docs/ARCHITECTURE.md), [Feature parity](docs/FEATURE_PARITY.md), [Migration plan](docs/MIGRATION_PLAN.md) and [Safety requirements](docs/SAFETY_REQUIREMENTS.md).

## Development

Requires Flutter stable with Linux desktop enabled and Python 3.10+.

```sh
flutter create --project-name droidlab_desktop --platforms=linux,windows,macos apps/desktop
cd apps/desktop
flutter pub get
flutter analyze
flutter test
```

The Flutter shell intentionally does not issue device commands yet. Backend operations will be exposed only through the validated protocol bridge.

## Safety

Device operations require explicit serial selection, fresh target validation, typed arguments and confirmation bound to the exact operation. Never interpret host-process cancellation as proof of device rollback. See [SAFETY_REQUIREMENTS.md](docs/SAFETY_REQUIREMENTS.md).

## License

Apache-2.0. See [LICENSE](https://github.com/augztn/DroidLab-Next/blob/main/LICENSE) while license and notices are carried into this repository.
