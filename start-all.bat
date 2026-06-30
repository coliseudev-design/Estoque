@echo off
echo ============================================================
echo  Coliseu Speed -- Ambiente Local Completo
echo ============================================================
echo.

echo [1/5] Coliseu.Identity API (porta 5170)...
start "Identity API" cmd /k "cd /d "%~dp0Coliseu.Identity\src\Coliseu.Identity.Api" && dotnet run --environment Development"
timeout /t 8 /nobreak > nul

echo [2/5] Middleware Node.js (porta 3001)...
start "Middleware" cmd /k "cd /d "%~dp0middleware" && npm start"
timeout /t 5 /nobreak > nul

echo [3/5] Admin Frontend React/Vite (porta 3100)...
start "Admin Frontend" cmd /k "cd /d "%~dp0Coliseu.Identity\admin-frontend" && npm run dev -- --port 3100"
timeout /t 3 /nobreak > nul

echo [4/5] ColiseuSpeed.Worker (Sincronizador Firebird)...
start "Worker" cmd /k "cd /d "%~dp0worker" && dotnet run --environment Development"
timeout /t 3 /nobreak > nul

echo [5/5] App Flutter Windows...
start "Flutter App" cmd /k "cd /d "%~dp0mobile" && flutter run -d windows --no-pub"

echo.
echo ============================================================
echo  Todos os servicos foram iniciados!
echo.
echo  Identity API  : http://localhost:5170
echo  Middleware    : http://localhost:3001
echo  Admin UI      : http://localhost:3100
echo ============================================================
pause
