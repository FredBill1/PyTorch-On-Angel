set IMAGE_NAME=pytorch_on_angel:artifacts

docker build --target ARTIFACTS -t %IMAGE_NAME% . || goto :error
docker run -it --rm -v %cd%/dist:/output %IMAGE_NAME% || goto :error
echo "***** output files in ./dist *****"
goto :success

:error
echo Failed with error #%errorlevel%.

:success
pause
