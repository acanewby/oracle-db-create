@echo off
rem ======================================
rem (c) 2018 Adrian Newby
rem ======================================
rem
rem The real work under Windows is done using PowerShell
rem This script merely wraps PowerShell to allow it to be launched
rem as if it were any other .CMD batch file
rem 
rem Two parameters are expected:
rem    1. Main config filename
rem    2. Tablespace config filename
rem
rem ======================================


echo.
echo.

powershell .\cr8-db.ps1 %1 %2

echo.
echo.
echo -------------------------------------------------------------------------------
goto answer%errorlevel%

:answer9009
echo Error: %ERRORLEVEL%
echo This script requires PowerShell, 
echo which does not appear to be installed correctly.
echo.
echo Refer to http://www.microsoft.com/windowsserver2003/technologies/management/powershell/default.msp
goto end

:answer1
echo Error: %ERRORLEVEL%
echo There was a problem running the script 
goto end


:answer0
echo Done
goto end




:end
echo -------------------------------------------------------------------------------
echo (c) Adrian Newby, 2018-
echo -------------------------------------------------------------------------------





