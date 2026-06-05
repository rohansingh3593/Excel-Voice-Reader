
# Write-Host "====================================="
# Write-Host "Branch Pull setup Started."
# Write-Host "====================================="
# $BRANCH_NAME = "codex/create-excel-voice-reader-app"
# # $BRANCH_NAME = "main"
# git pull origin $BRANCH_NAME
# Write-Host "====================================="
# Write-Host "Branch Pull setup completed."
# Write-Host "====================================="

Write-Host "====================================="
Write-Host "Environment setup Started."
Write-Host "====================================="
flutter clean
flutter pub get
Write-Host ""
Write-Host "====================================="
Write-Host "Environment setup completed."
Write-Host "====================================="
Write-Host "Application Running"
# flutter config --enable-windows-desktop
# flutter config --enable-web
# flutter create .
# flutter run -d windows


# taskkill /F /IM bubble_time_progress_app.exe
# taskkill /F /IM flutter_tester.exe
# taskkill /F /IM dart.exe

# Default build for easy installation with Play Protect
flutter build apk --release --flavor safe
