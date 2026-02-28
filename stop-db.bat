@echo off
echo Stopping MariaDB...
"%~dp0mariadb\mariadb-11.4.4-winx64\bin\mysqladmin.exe" -u root shutdown
echo MariaDB stopped.
pause
