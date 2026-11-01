# DroidLab Desktop

Flutter desktop composition root. Generate native runner projects from this directory once:

```sh
flutter create --project-name droidlab_desktop --platforms=linux,windows,macos .
flutter pub get
flutter run -d linux
```

The app depends on shared Dart packages in the repository's `packages/` directory and starts the headless Python service from `backend/python/server.py`.
