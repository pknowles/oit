
if exist vs\bin_x64\oit_Release_x64.exe (
	set getexe=vs\bin_x64\oit_Release_x64.exe
	set exe=oit_Release_x64.exe
) else if exist vs\bin_x32\oit_Release_x32.exe (
	set getexe=vs\bin_x32\oit_Release_x32.exe
	set exe=oit_Release_x32.exe
) else if exist vs\bin_x64\oit_Debug_x64.exe (
	set getexe=vs\bin_x64\oit_Debug_x64.exe
	set exe=oit_Debug_x64.exe
) else if exist vs\bin_x32\oit_Debug_x32.exe (
	set getexe=vs\bin_x32\oit_Debug_x32.exe
	set exe=oit_Debug_x32.exe
) else (
	echo No executables found. Please build one.
	pause
	exit /b 1
)

copy %getexe% %exe%

for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /format:list') do set datetime=%%I
set datetime=%datetime:~0,8%_%datetime:~8,6%

if not exist results mkdir results

rem %exe% -r tests/lfb.xml > results\log_lfb_%datetime%.txt 2>&1
rem timeout /t 3
rem move benchmark.csv results\lfb_%datetime%.csv

%exe% -r tests/all.xml > results\log_all_%datetime%.txt 2>&1
timeout /t 3
move benchmark.csv results\all_%datetime%.csv

%exe% -r tests/coherent_oit.xml > results\log_clfb_%datetime%.txt 2>&1
timeout /t 3
move benchmark.csv results\clfb_%datetime%.csv