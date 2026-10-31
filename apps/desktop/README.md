# DroidLab Desktop

Flutter desktop application workspace. Generate platform runners from the repository root with the supported Flutter stable SDK:

```sh
flutter create --project-name droidlab_desktop --platforms=linux,windows,macos apps/desktop
```

Keep generated platform runner files under this directory. The app source imports shared package modules from the monorepo.
