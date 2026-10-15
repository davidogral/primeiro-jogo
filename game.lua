-- Loader: roda o jogo (jogo.lua) protegido. O console nao mostra log, entao qualquer erro
-- (de carga ou dentro do update) aparece NA TELA em vez de deixar a tela preta.
local ok, err = pcall(require, "jogo")
local jogo_update = update
local erro = (not ok) and tostring(err) or nil
if not erro and type(jogo_update) ~= "function" then erro = "jogo.lua nao definiu update()" end

local function mostra_erro()
  ui.camera(0, 0); ui.clip(0, 0, 480, 270)
  ui.palset(1, 0x7FFF)                       -- branco (igual em RGB555 e BGR555)
  ui.palset(2, 0x03FF)                       -- amarelo em BGR555 / ciano em RGB555
  ui.cls(0)
  ui.print("ERRO NO JOGO (tire uma foto e mande):", 8, 8, 2)
  local y, i = 24, 1
  while i <= #erro and y < 262 do
    ui.print(string.sub(erro, i, i + 76), 8, y, 1)
    i, y = i + 77, y + 10
  end
end

function update(frame)
  ui.clip(0, 0, 480, 270)       -- igual ao primeiro-jogo oficial: clip e camera explicitos todo frame
  ui.camera(0, 0)
  if not erro then
    local ok2, e2 = pcall(jogo_update, frame)
    if not ok2 then erro = tostring(e2) end
  end
  if erro then mostra_erro() end
end
