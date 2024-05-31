@echo off
REM Check if at least one argument is passed
if "%~1"=="" (
    echo Usage: %~nx0 ^<model_name^>
    exit /b 1
)

REM Model name from command line argument
set "model_name=%~1"

REM Download YOLOv7 ONNX model
echo Downloading ONNX model %model_name%...
curl -L "https://github.com/levipereira/triton-server-yolo-v7-v9/releases/download/v0.0.1/%model_name%.onnx" -o "%model_name%.onnx"

REM Check if download was successful
if %ERRORLEVEL% EQU 0 (
    echo ONNX model %model_name% downloaded successfully.
) else (
    echo Failed to download ONNX model %model_name%.
    exit /b 1
)
