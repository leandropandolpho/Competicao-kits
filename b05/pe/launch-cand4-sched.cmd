@echo off
rem launch-cand4-sched.cmd - roda a bateria candidata 4 via AGENDADOR DE TAREFAS (contexto limpo, fora do Job do console).
rem Cria uma tarefa ONCE no contexto do usuario e dispara na hora; a bateria roda parentada pelo servico do Agendador,
rem NAO pelo Explorer/cmd -> o reaping de neto do Job Object volta a funcionar (conserta o PE sem precisar do shell direto).
setlocal
set BASE=C:\Users\piloto\piloto\gate-pe-083
set TN=B05Cand4Sched
set OUT=%BASE%\sched-out.txt
echo [sched] inicio %DATE% %TIME% > "%OUT%"
schtasks /delete /tn "%TN%" /f >nul 2>&1
schtasks /create /tn "%TN%" /sc once /st 23:59 /rl LIMITED /f ^
 /tr "\"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe\" -NoProfile -ExecutionPolicy Bypass -File \"%BASE%\boot-cand4.ps1\"" >> "%OUT%" 2>&1
echo [sched] create rc=%ERRORLEVEL% >> "%OUT%"
schtasks /run /tn "%TN%" >> "%OUT%" 2>&1
echo [sched] run rc=%ERRORLEVEL% >> "%OUT%"
echo [sched] disparada; acompanhe boot-cand4.txt e cand4-resultado-*.txt >> "%OUT%"
echo CONCLUIDO - pode fechar.
