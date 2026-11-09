# Ejecutar desde la RAIZ del proyecto App-Mundicam-2 en PowerShell.
# 1) Mantener abierto en OTRA consola el túnel SSH autorizado al VPS:
#    ssh -N -L 8770:127.0.0.1:8770 mundicam-agent@<HOST_VPS>
# 2) Tener Android Studio y un emulador Android iniciado.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path './pubspec.yaml')) {
  throw 'Abre el terminal en la raiz del proyecto Flutter.'
}
if (-not (Test-Path './lib/main_qa.dart')) {
  throw 'Falta el paquete MundiCam Android QA.'
}

$devices = @(adb devices | Select-String '^(emulator-[0-9]+)\s+device$')
if ($devices.Count -ne 1) {
  throw 'Inicia exactamente un emulador Android en Android Studio y ejecuta de nuevo.'
}
$serial = $devices[0].Matches[0].Groups[1].Value

# El teléfono emulado llegará a 127.0.0.1:8770 a través del PC.
adb -s $serial reverse tcp:8770 tcp:8770
if ($LASTEXITCODE -ne 0) { throw 'No se pudo establecer adb reverse.' }

# El ID .qa evita sobrescribir la app real instalada en el dispositivo.
$env:MUNDICAM_ANDROID_QA = '1'
try {
  flutter run --debug --device-id $serial --target lib/main_qa.dart
} finally {
  Remove-Item Env:MUNDICAM_ANDROID_QA -ErrorAction SilentlyContinue
}
