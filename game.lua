-- DUELO CORINGA - LUPI (480x270 @ 60fps)  -- tema da jam: FALHA NO SISTEMA
-- 1 jogador vs CPU, controle de Super Nintendo (pad 0). Todos os botoes tem mecanica:
--   SNES     teclado  constante        mecanica
--   direcional WASD   UP/DOWN/LEFT/RIGHT move
--   B        K        BTN_Z            tiro
--   A        J        6 (RIGHT_FACE_RIGHT) segurar carrega, soltar = LASER (apaga tiros, quebra escudo)
--   Y        M        BTN_E            escudo (segurar; gasta energia, pode quebrar)
--   X        L        BTN_Q            DEBUG: cancela a falha atual (cargas por rodada)
--   L        G        BTN_F            dash com invencibilidade
--   R        H        BTN_G            tiro em leque (3 tiros)
--   START    -        15 (MIDDLE_RIGHT) pausa (so controle: lupinho nao mapeia tecla)
--   SELECT   -        13 (MIDDLE_LEFT)  na pausa/fim: volta ao titulo
-- Eventos aleatorios (aviso -> efeito) mudam as regras. O principal: INVERSAO.
-- Para adaptar ao tema da jam: escolha/edite um tema em TEMAS e troque TEMA_ATUAL.

-- ================= CONFIG =================
local TEMA_ATUAL = "falha"    -- falha | padrao | espaco | faroeste | magia
-- Input (lupinho 1.1.0): BTN_Z = GAMEPAD RIGHT_FACE_DOWN = tecla K; direcional = WASD.
-- O teclado e checado ignorando o pad, e o console tem 1 controle (pad 0).
local PAD1 = 0
local ACAO = BTN_Z           -- em menus: B, A ou START confirmam
local BTN_A_SNES, BTN_START, BTN_SELECT = 6, 15, 13
local B_TIRO, B_LASER, B_ESCUDO, B_DEBUG, B_DASH, B_LEQUE = BTN_Z, BTN_A_SNES, BTN_E, BTN_Q, BTN_F, BTN_G
local VIDAS = 3
local VEL, VEL_TIRO, RECARGA = 3, 6, 18
local AVISO_FRAMES = 90                       -- 1.5s de aviso
local INTERVALO_MIN, INTERVALO_MAX = 360, 720 -- 6s a 12s entre eventos
local RODADAS_PARA_VENCER = 2                 -- melhor de 3
local CONTAGEM_PASSO, CONTAGEM_JA = 45, 30    -- frames de cada "3, 2, 1" e do "JA!"
local PAUSA_RODADA = 120                      -- frames mostrando quem venceu a rodada
local YMIN, YMAX = 24, 240                    -- area de jogo (embaixo fica o HUD de habilidades)
-- Habilidades
local ESC_MAX, ESC_REGEN = 120, 0.4           -- escudo: energia (1/frame em uso) e regeneracao
local CARGA_MIN, CARGA_MAX, LASER_CD = 30, 45, 150
local DASH_T, DASH_VEL, DASH_CD = 10, 8, 75
local LEQUE_CD, LEQUE_VY = 90, 1.5
local DEBUG_CARGAS = 1                        -- DEBUGs do jogador por rodada

-- ================= CPU (IA por regras) =================
-- reacao: frames entre decisoes | erro: +-px no Y mirado | desvio: chance de fugir de tiro
-- preve: quanto antecipa o movimento do jogador (0-1) | escudo/dash/leque/laser: chance de usar
-- debug: DEBUGs por rodada | vel/rec/tiro: multiplicadores da CPU | vidas: vidas da CPU | faixa: limite do adaptativo
local DIFICULDADES = {
  facil   = { nome = "FACIL", curto = "FACIL", desc = "para aquecer",
              reacao = 24, erro = 30, desvio = 0.3, preve = 0, escudo = 0, dash = 0, leque = 0, laser = 0, debug = 0,
              vel = 0.9, rec = 1, tiro = 1, vidas = 3, faixa = 0.3 },
  medio   = { nome = "MEDIO", curto = "MEDIO", desc = "a CPU ja se defende",
              reacao = 12, erro = 14, desvio = 0.6, preve = 0.2, escudo = 0.25, dash = 0.2, leque = 0.15, laser = 0, debug = 0,
              vel = 1.05, rec = 1, tiro = 1, vidas = 3, faixa = 0.3 },
  dificil = { nome = "DIFICIL", curto = "DIFICIL", desc = "usa tudo, preve seus movimentos",
              reacao = 5, erro = 3, desvio = 0.85, preve = 0.6, escudo = 0.5, dash = 0.5, leque = 0.35, laser = 0.25, debug = 1,
              vel = 1.2, rec = 0.8, tiro = 1.2, vidas = 4, faixa = 0.2 },
  critico = { nome = "SISTEMA CRITICAMENTE COMPROMETIDO", curto = "CRITICO", desc = "quase impossivel",
              reacao = 1, erro = 0, desvio = 0.97, preve = 1, escudo = 0.9, dash = 0.9, leque = 0.6, laser = 0.5, debug = 3,
              vel = 1.5, rec = 0.5, tiro = 1.5, vidas = 6, faixa = 0.05, bloqueado = true },
}
local ORDEM_DIF = { "facil", "medio", "dificil", "critico" }
local DIF_INICIAL = 2
local AJUSTE = 0.15          -- adaptativo: +-15% por vida perdida a favor de quem perde
local CONFUSAO = 30          -- frames que a CPU anda errado no inicio do "inverte"
local ALINHADO = 10          -- px de diferenca no Y para a CPU considerar que esta na mira

-- ================= PALETA =================
local PAL = { 0x0000, 0x7FFF, 0x001F, 0x7C00, 0x03FF, 0x294A, 0x7C1F, 0x03E0, 0x0C63, 0x01BF }
for i = 1, #PAL do ui.palset(i - 1, PAL[i]) end
local PRETO, BRANCO, VERM, AZUL, AMAR, CINZA, ROXO, VERDE, ESCURO, LARANJA = 0,1,2,3,4,5,6,7,8,9

local W, H = 480, 270
local MEIO = W / 2

-- ================= EVENTOS =================
local EVENTOS = {
  inverte = { nome = "INVERTIDO", cor = ROXO,    dur = 300, inv = true },
  turbo   = { nome = "TURBO",     cor = LARANJA, dur = 240, vel = 2 },
  lama    = { nome = "LENTO",     cor = CINZA,   dur = 240, vel = 0.4 },
  rajada  = { nome = "RAJADA",    cor = VERDE,   dur = 240, rec = 0.3, tiro = 1.5 },
}
for k, e in pairs(EVENTOS) do e.id = k end

-- ================= TEMAS =================
local TEMAS = {
  falha = {
    titulo = "FALHA NO SISTEMA", nome1 = "NAVE", nome2 = "VIRUS.EXE",
    cor1 = VERDE, cor2 = VERM, fundo_cor = PRETO, fundo = "estrelas", glitch = true,
    forma = "nave", tiro_forma = "quad", aviso = "ERRO CRITICO DETECTADO",
    vitoria = " VENCEU!", eventos = { "inverte", "inverte", "turbo", "lama", "rajada" },
    nomes = { inverte = "CONTROLES CORROMPIDOS", turbo = "OVERCLOCK", lama = "LAG", rajada = "BUFFER OVERFLOW" },
  },
  padrao = {
    titulo = "DUELO INVERTIDO", nome1 = "VOCE", nome2 = "CPU",
    cor1 = AZUL, cor2 = VERM, fundo_cor = PRETO, fundo = "nada",
    forma = "quad", tiro_forma = "quad", aviso = "!! ATENCAO !!",
    vitoria = " VENCEU!", eventos = { "inverte", "inverte", "turbo", "rajada" },
  },
  espaco = {
    titulo = "GUERRA ORBITAL", nome1 = "NAVE A", nome2 = "NAVE B",
    cor1 = VERDE, cor2 = ROXO, fundo_cor = PRETO, fundo = "estrelas",
    forma = "tri", tiro_forma = "circ", aviso = "ANOMALIA GRAVITACIONAL",
    vitoria = " DOMINA A ORBITA!", eventos = { "inverte", "inverte", "lama", "turbo" },
  },
  faroeste = {
    titulo = "DUELO AO SOL", nome1 = "XERIFE", nome2 = "BANDIDO",
    cor1 = AMAR, cor2 = VERM, fundo_cor = ESCURO, fundo = "chao",
    forma = "quad", tiro_forma = "quad", aviso = "TEMPESTADE DE AREIA",
    vitoria = " E O MAIS RAPIDO!", eventos = { "inverte", "inverte", "rajada", "lama" },
  },
  magia = {
    titulo = "DUELO ARCANO", nome1 = "MAGO", nome2 = "BRUXA",
    cor1 = AZUL, cor2 = ROXO, fundo_cor = PRETO, fundo = "estrelas",
    forma = "circ", tiro_forma = "circ", aviso = "FEITICO DO CAOS",
    vitoria = " VENCEU O DUELO!", eventos = { "inverte", "inverte", "turbo", "rajada" },
  },
}
local T = TEMAS[TEMA_ATUAL]

-- ================= ESTADO =================
local estado = "titulo"
local dif_idx, dif, hud2 = DIF_INICIAL, nil, ""
local desbloqueado, novo_desbloq = false, false   -- CRITICO libera ao vencer o DIFICIL (vale ate desligar)
local estado_ant, msg_t, msg_txt = "jogo", 0, ""
local TXT_NUM = { [0] = "0", "1", "2", "3" }
local frame, shake, vencedor, players
local placar, rodada, cont_t = { 0, 0 }, 1, 0
local TXT_CONT = { "1", "2", "3" }
local fase, timer, evento, prox_evento

local MAX_TIROS, MAX_PART = 40, 60
local tiros, parts = {}, {}
for i = 1, MAX_TIROS do tiros[i] = { ativo = false, x = 0, y = 0, dir = 0, dono = 0, v = 0, vy = 0, w = 5, h = 5, laser = false } end
for i = 1, MAX_PART do parts[i] = { vida = 0, x = 0, y = 0, vx = 0, vy = 0, cor = 0 } end

local estrelas = {}
for i = 1, 40 do estrelas[i] = { x = math.random(0, W), y = math.random(0, H), v = math.random(1, 3) } end

-- ================= UTIL =================
local function apertou(b)
  if b == ACAO then
    return ui.btnp(BTN_Z, PAD1) or ui.btnp(BTN_A_SNES, PAD1) or ui.btnp(BTN_START, PAD1)
  end
  return ui.btnp(b, PAD1)
end
local function segurando(b) return ui.btn(b, PAD1) end
local function centro(txt, y, cor)
  ui.print(txt, math.floor(W / 2 - #txt * 3), y, cor)
end

local function nome_ev(e) return (T.nomes and T.nomes[e.id]) or e.nome end

local function mod(campo)
  if fase == "ativo" and evento[campo] then return evento[campo] end
  return 1
end

local function explode(x, y, cor, n)
  for i = 1, MAX_PART do
    local p = parts[i]
    if p.vida <= 0 then
      p.vida, p.x, p.y, p.cor = 20 + math.random(0, 15), x, y, cor
      p.vx, p.vy = math.random(-30, 30) / 10, math.random(-30, 30) / 10
      n = n - 1
      if n <= 0 then return end
    end
  end
end

local function forma(f, x, y, w, h, cor, dir)
  if f == "tri" then
    if dir == 1 then ui.trisfill(x, y, x, y + h, x + w, y + h / 2, cor)
    else ui.trisfill(x + w, y, x + w, y + h, x, y + h / 2, cor) end
  elseif f == "nave" then
    local tras, ponta = dir == 1 and x or x + w, dir == 1 and x + w or x
    ui.trisfill(tras, y, tras, y + h, ponta, y + h / 2, cor)
    local mx = dir == 1 and x - 4 or x + w
    if (frame // 4) % 2 == 0 then
      ui.rectfill(mx, y + 2, mx + 4, y + 5, LARANJA); ui.rectfill(mx, y + h - 5, mx + 4, y + h - 2, LARANJA)
    end
    ui.circfill(x + w / 2, y + h / 2, 2, BRANCO)
  elseif f == "circ" then
    ui.circfill(x + w / 2, y + h / 2, w / 2, cor)
  else
    ui.rectfill(x, y, x + w, y + h, cor)
  end
end

-- ================= LOGICA =================
local nova_rodada

local function sorteia_evento()
  local lista = T.eventos
  prox_evento = EVENTOS[lista[math.random(1, #lista)]]
end

local function novo_player(id, x, cor, dir)
  return { id = id, x = x, y = H / 2 - 8, w = 16, h = 16, cor = cor,
           dir = dir, vidas = VIDAS, recarga = 0, hit = 0, vy_ult = 0,
           -- habilidades
           energia = ESC_MAX, escudo = false, quebrado = false, carga = 0, laser_cd = 0,
           dash_t = 0, dash_dir = 0, dash_cd = 0, leque_cd = 0, debug = 0,
           -- so a CPU usa: parametros atuais da IA e estado da decisao
           cpu = id == 2, reacao = 0, erro = 0, desvio = 0, cont = 0, alvo_y = H / 2 - 8, quer_atirar = false,
           escudo_t = 0, carregando = 0, dash_pref = 1 }
end

-- Reinicia so a rodada (vidas, posicoes, tiros, eventos); mantem placar e o ajuste da IA.
nova_rodada = function()
  for i = 1, 2 do
    local p = players[i]
    p.y, p.vidas, p.recarga, p.hit = H / 2 - 8, p.cpu and dif.vidas or VIDAS, 0, 0
    p.x = i == 1 and 30 or W - 46
    p.cont, p.quer_atirar, p.alvo_y = 0, false, p.y
    p.energia, p.escudo, p.quebrado, p.carga, p.laser_cd = ESC_MAX, false, false, 0, 0
    p.dash_t, p.dash_cd, p.leque_cd, p.escudo_t, p.carregando = 0, 0, 0, 0, 0
    p.debug = p.cpu and dif.debug or DEBUG_CARGAS
  end
  for i = 1, MAX_TIROS do tiros[i].ativo = false end
  shake, vencedor, msg_t = 0, nil, 0
  fase, timer, evento = "normal", math.random(INTERVALO_MIN, INTERVALO_MAX), nil
  sorteia_evento()
  estado, cont_t = "contagem", 3 * CONTAGEM_PASSO + CONTAGEM_JA
end

local function reset()
  dif = DIFICULDADES[ORDEM_DIF[dif_idx]]
  hud2 = T.nome2 .. " [" .. dif.curto .. "]"
  players = { novo_player(1, 30, T.cor1, 1), novo_player(2, W - 46, T.cor2, -1) }
  local c = players[2]
  c.reacao, c.erro, c.desvio = dif.reacao, dif.erro, dif.desvio
  placar[1], placar[2], rodada = 0, 0, 1
  frame, novo_desbloq = 0, false
  nova_rodada()
end

local function atualiza_eventos()
  timer = timer - 1
  if timer > 0 then return end
  if fase == "normal" then
    fase, timer = "aviso", AVISO_FRAMES
  elseif fase == "aviso" then
    evento, fase, timer = prox_evento, "ativo", prox_evento.dur
    shake = 10
  else
    local vmin = math.min(players[1].vidas, players[2].vidas)
    local f = 0.5 + 0.5 * (vmin / VIDAS)
    fase, timer, evento = "normal", math.floor(math.random(INTERVALO_MIN, INTERVALO_MAX) * f), nil
    sorteia_evento()
  end
end

local function atirar(p, vy, laser)
  for i = 1, MAX_TIROS do
    local t = tiros[i]
    if not t.ativo then
      t.ativo, t.dono, t.dir, t.vy, t.laser = true, p.id, p.dir, vy, laser
      t.w, t.h = laser and 16 or 5, laser and 6 or 5
      t.v = VEL_TIRO * mod("tiro") * (p.cpu and dif.tiro or 1) * (laser and 1.6 or 1)
      t.x = p.x + (p.dir == 1 and p.w or -t.w)
      t.y = p.y + p.h / 2 - t.h / 2
      return
    end
  end
end

-- X / DEBUG: cancela o aviso ou a falha ativa para os dois lados
local function cancela_falha(p)
  p.debug = p.debug - 1
  fase, timer, evento = "normal", math.random(INTERVALO_MIN, INTERVALO_MAX), nil
  sorteia_evento()
  shake, msg_t = 6, 90
  msg_txt = p.cpu and (T.nome2 .. " APLICOU PATCH") or "PATCH APLICADO: FALHA CANCELADA"
end

-- Dificuldade adaptativa: perdeu_cpu=true -> CPU melhora; false -> CPU piora. Nunca sai da faixa.
local function ajusta_ia(perdeu_cpu)
  local c = players[2]
  local f, fx = perdeu_cpu and (1 - AJUSTE) or (1 + AJUSTE), dif.faixa
  c.reacao = ui.mid(dif.reacao * (1 - fx), c.reacao * f, dif.reacao * (1 + fx))
  c.erro   = ui.mid(dif.erro * (1 - fx), c.erro * f, dif.erro * (1 + fx))
  c.desvio = ui.mid(dif.desvio * (1 - fx), c.desvio / f, math.min(1, dif.desvio * (1 + fx)))
end

-- Decide a cada `reacao` frames: mira no Y do jogador (+-erro, antecipando com `preve`), reage a tiros
-- (desvia, dash ou escudo), escolhe ataque (tiro, leque, laser) e usa DEBUG contra o "inverte".
-- Retorna os mesmos comandos que o jogador gera com o controle.
local function pensa_cpu(c)
  local alvo = players[1]
  local dash, leque, laser, debug = false, false, false, false
  if c.escudo_t > 0 then c.escudo_t = c.escudo_t - 1 end
  -- carregando laser: fica parada ate disparar (brecha para o jogador)
  if c.carregando > 0 then
    c.carregando = c.carregando - 1
    return 0, 0, false, false, false, false, c.carregando == 0, true, false
  end
  c.cont = c.cont - 1
  if c.cont <= 0 then
    c.cont = math.max(1, math.floor(c.reacao + 0.5))
    local e = math.floor(c.erro + 0.5)
    local prev = alvo.vy_ult * ((c.x - alvo.x) / (VEL_TIRO * dif.tiro)) * dif.preve
    c.alvo_y = ui.mid(YMIN, alvo.y + prev + math.random(-e, e), YMAX)
    -- ameaca mais proxima: tiro do jogador que vai cruzar a faixa da CPU
    local amea, dist = nil, 9999
    for i = 1, MAX_TIROS do
      local t = tiros[i]
      if t.ativo and t.dono == 1 and t.x < c.x + c.w then
        local d = c.x - t.x
        local ty = t.y + t.vy * (d / t.v)
        if ty + t.h > c.y - 4 and ty < c.y + c.h + 4 and d < dist then amea, dist = t, d end
      end
    end
    if amea then
      local fuga = (amea.y + amea.h / 2 < c.y + c.h / 2) and 1 or -1
      if math.random() < c.desvio then
        if c.dash_cd <= 0 and dist < 120 and math.random() < dif.dash then
          dash, c.dash_pref = true, fuga
        else
          if fuga == 1 then c.alvo_y = amea.y + amea.h + 6 else c.alvo_y = amea.y - c.h - 6 end
          if c.alvo_y < YMIN then c.alvo_y = amea.y + amea.h + 6 elseif c.alvo_y > YMAX then c.alvo_y = amea.y - c.h - 6 end
        end
      elseif not amea.laser and dist < 90 and not c.quebrado and math.random() < dif.escudo then
        c.escudo_t = 25
      end
    end
    local dy_alvo = math.abs(c.y - alvo.y)
    c.quer_atirar = dy_alvo < ALINHADO
    if dy_alvo >= ALINHADO and dy_alvo < 60 and c.leque_cd <= 0 and math.random() < dif.leque then leque = true end
    if dy_alvo < ALINHADO and c.laser_cd <= 0 and not amea and math.random() < dif.laser then c.carregando = CARGA_MIN end
    if fase == "ativo" and evento.inv and c.debug > 0 and (evento.dur - timer) >= CONFUSAO then debug = true end
  end
  local dy, diff = 0, c.alvo_y - c.y
  if diff > 2 then dy = 1 elseif diff < -2 then dy = -1 end
  if dash then dy = c.dash_pref end
  -- no "inverte" a CPU tambem fica confusa: anda errado nos primeiros CONFUSAO frames, depois compensa
  if fase == "ativo" and evento.inv and (evento.dur - timer) < CONFUSAO then dy = -dy end
  local atira = c.quer_atirar and math.abs(c.y - alvo.y) < ALINHADO
  return 0, dy, atira, c.escudo_t > 0, dash, leque, laser, false, debug
end

-- dx, dy, atira, escudo, dash, leque, laser (dispara agora), carregando, debug
local function le_controle(p)
  local dx, dy = 0, 0
  if segurando(LEFT) then dx = dx - 1 end
  if segurando(RIGHT) then dx = dx + 1 end
  if segurando(UP) then dy = dy - 1 end
  if segurando(DOWN) then dy = dy + 1 end
  if fase == "ativo" and evento.inv then dx, dy = -dx, -dy end
  local laser, carregando = false, false
  if segurando(B_LASER) and p.laser_cd <= 0 then
    p.carga, carregando = math.min(CARGA_MAX, p.carga + 1), true
  elseif p.carga > 0 then
    laser, p.carga = p.carga >= CARGA_MIN, 0
  end
  return dx, dy, ui.btnp(B_TIRO, PAD1), segurando(B_ESCUDO), ui.btnp(B_DASH, PAD1), ui.btnp(B_LEQUE, PAD1),
         laser, carregando, ui.btnp(B_DEBUG, PAD1)
end

local function atualiza_player(p)
  local dx, dy, atira, escudo, dash, leque, laser, carregando, debug
  if p.cpu then dx, dy, atira, escudo, dash, leque, laser, carregando, debug = pensa_cpu(p)
  else dx, dy, atira, escudo, dash, leque, laser, carregando, debug = le_controle(p) end

  -- Y: escudo
  if escudo and not p.quebrado and p.energia > 0 then
    p.escudo, p.energia = true, p.energia - 1
    if p.energia <= 0 then p.quebrado, p.escudo = true, false; explode(p.x + 8, p.y + 8, AMAR, 8) end
  else
    p.escudo = false
    p.energia = math.min(ESC_MAX, p.energia + ESC_REGEN)
    if p.quebrado and p.energia >= ESC_MAX / 2 then p.quebrado = false end
  end

  -- L: dash
  if p.dash_cd > 0 then p.dash_cd = p.dash_cd - 1 end
  if dash and p.dash_cd <= 0 and p.dash_t <= 0 then
    p.dash_t, p.dash_cd = DASH_T, DASH_CD
    p.dash_dir = dy ~= 0 and dy or (p.y > (YMIN + YMAX) / 2 and -1 or 1)
  end

  local y0 = p.y
  if p.dash_t > 0 then
    p.dash_t = p.dash_t - 1
    p.y = p.y + p.dash_dir * DASH_VEL
    if p.dash_t % 2 == 0 then explode(p.x + 8, p.y + 8, p.cor, 1) end
  else
    local v = VEL * mod("vel") * (p.cpu and dif.vel or 1)
    if p.escudo or carregando then v = v * 0.5 end
    p.x, p.y = p.x + dx * v, p.y + dy * v
  end
  if p.id == 1 then p.x = ui.mid(0, p.x, MEIO - p.w - 4)
  else p.x = ui.mid(MEIO + 4, p.x, W - p.w) end
  p.y = ui.mid(YMIN, p.y, YMAX)
  p.vy_ult = p.y - y0

  if p.recarga > 0 then p.recarga = p.recarga - 1 end
  if p.leque_cd > 0 then p.leque_cd = p.leque_cd - 1 end
  if p.laser_cd > 0 then p.laser_cd = p.laser_cd - 1 end
  if p.hit > 0 then p.hit = p.hit - 1 end
  if p.escudo then return end   -- de escudo nao atira
  -- B: tiro
  if atira and p.recarga <= 0 then
    atirar(p, 0, false)
    p.recarga = math.floor(RECARGA * mod("rec") * (p.cpu and dif.rec or 1))
    p.quer_atirar = false
  end
  -- R: leque
  if leque and p.leque_cd <= 0 then
    atirar(p, -LEQUE_VY, false); atirar(p, 0, false); atirar(p, LEQUE_VY, false)
    p.leque_cd = math.floor(LEQUE_CD * mod("rec") * (p.cpu and dif.rec or 1))
  end
  -- A: laser
  if laser and p.laser_cd <= 0 then
    atirar(p, 0, true)
    p.laser_cd, shake = LASER_CD, 4
  end
  -- X: DEBUG
  if debug and p.debug > 0 and fase ~= "normal" then cancela_falha(p) end
end

local function atualiza_tiros()
  for i = 1, MAX_TIROS do
    local t = tiros[i]
    if t.ativo then
      t.x, t.y = t.x + t.dir * t.v, t.y + t.vy
      if t.x < -20 or t.x > W + 20 or t.y < YMIN - 8 or t.y > YMAX + 20 then t.ativo = false end
      -- laser apaga tiros inimigos no caminho
      if t.ativo and t.laser then
        for j = 1, MAX_TIROS do
          local o = tiros[j]
          if o.ativo and o.dono ~= t.dono and not o.laser and o.x < t.x + t.w and o.x + o.w > t.x
             and o.y < t.y + t.h and o.y + o.h > t.y then
            o.ativo = false; explode(o.x, o.y, BRANCO, 2)
          end
        end
      end
      local alvo = players[t.dono == 1 and 2 or 1]
      if t.ativo and estado == "jogo" and alvo.hit == 0 and alvo.dash_t == 0 and t.x < alvo.x + alvo.w
         and t.x + t.w > alvo.x and t.y < alvo.y + alvo.h and t.y + t.h > alvo.y then
       if alvo.escudo and not t.laser then
        t.ativo = false
        explode(t.x, t.y, AMAR, 3)
       else
        if alvo.escudo then alvo.escudo, alvo.quebrado, alvo.energia = false, true, 0 end
        t.ativo = false
        alvo.vidas, alvo.hit, shake = alvo.vidas - 1, 45, 12
        ajusta_ia(alvo.cpu)
        explode(alvo.x + 8, alvo.y + 8, alvo.cor, 12)
        if alvo.vidas <= 0 then
          explode(alvo.x + 8, alvo.y + 8, BRANCO, 25)
          placar[t.dono] = placar[t.dono] + 1
          vencedor, shake = t.dono, 25
          if placar[t.dono] >= RODADAS_PARA_VENCER then
            estado = "fim"
            if t.dono == 1 and ORDEM_DIF[dif_idx] == "dificil" and not desbloqueado then
              desbloqueado, novo_desbloq = true, true
            end
          else estado, cont_t = "entre", PAUSA_RODADA end
        end
       end
      end
    end
  end
  for i = 1, MAX_PART do
    local p = parts[i]
    if p.vida > 0 then p.x, p.y, p.vida = p.x + p.vx, p.y + p.vy, p.vida - 1 end
  end
end

-- ================= DESENHO =================
local function desenha_fundo()
  ui.cls(T.fundo_cor)
  if T.fundo == "estrelas" then
    for i = 1, #estrelas do
      local s = estrelas[i]
      s.x = s.x - s.v * 0.5
      if s.x < 0 then s.x = W end
      ui.rectfill(s.x, s.y, s.x + 1, s.y + 1, s.v == 3 and BRANCO or CINZA)
    end
  elseif T.fundo == "chao" then
    for y = 40, H, 30 do ui.line(0, y, W, y, CINZA) end
  end
  for y = 24, H, 12 do ui.line(MEIO, y, MEIO, y + 5, CINZA) end
  -- FALHA NO SISTEMA: faixas de glitch quando um evento esta vindo/ativo (e de leve no titulo)
  local critico = ORDEM_DIF[dif_idx] == "critico"
  if T.glitch and (fase ~= "normal" or estado == "titulo" or critico) and math.random() < (fase == "normal" and (critico and 0.3 or 0.15) or 0.5) then
    for i = 1, math.random(1, 4) do
      local gy = math.random(0, H - 4)
      local gx = math.random(-40, W - 40)
      ui.rectfill(gx, gy, gx + math.random(20, 160), gy + math.random(1, 3), math.random(0, 1) == 0 and VERDE or ROXO)
    end
  end
end

local function desenha_hud()
  local n1 = T.nome1
  ui.print(n1, 8, 6, T.cor1)
  for i = 1, players[1].vidas do ui.rectfill(12 + #n1 * 6 + i * 10, 6, 18 + #n1 * 6 + i * 10, 12, T.cor1) end
  local n2 = hud2
  ui.print(n2, W - 8 - #n2 * 6, 6, T.cor2)
  for i = 1, players[2].vidas do
    local x = W - 14 - #n2 * 6 - i * 10
    ui.rectfill(x, 6, x + 6, 12, T.cor2)
  end
  -- habilidades do jogador (embaixo, esquerda): Y escudo | A laser | L dash | R leque | X debug
  local p, y = players[1], H - 11
  ui.print("Y", 6, y, BRANCO)
  ui.rect(14, y, 54, y + 6, CINZA)
  ui.rectfill(14, y, 14 + math.floor(40 * p.energia / ESC_MAX), y + 6, p.quebrado and CINZA or AZUL)
  ui.print("A", 62, y, BRANCO)
  ui.rect(70, y, 100, y + 6, CINZA)
  if p.laser_cd > 0 then ui.rectfill(70, y, 70 + math.floor(30 * (1 - p.laser_cd / LASER_CD)), y + 6, CINZA)
  else ui.rectfill(70, y, 70 + math.floor(30 * p.carga / CARGA_MAX), y + 6, p.carga >= CARGA_MIN and BRANCO or AMAR) end
  ui.print("L", 108, y, BRANCO); ui.rectfill(116, y, 122, y + 6, p.dash_cd <= 0 and VERDE or CINZA)
  ui.print("R", 130, y, BRANCO); ui.rectfill(138, y, 144, y + 6, p.leque_cd <= 0 and VERDE or CINZA)
  ui.print("X", 152, y, BRANCO); ui.print(TXT_NUM[p.debug] or "+", 160, y, p.debug > 0 and AMAR or CINZA)
  -- escudo da CPU (embaixo, direita)
  local c = players[2]
  ui.rect(W - 54, y, W - 14, y + 6, CINZA)
  ui.rectfill(W - 54, y, W - 54 + math.floor(40 * c.energia / ESC_MAX), y + 6, c.quebrado and CINZA or T.cor2)
  ui.print("Y", W - 10, y, BRANCO)
end

local function desenha_evento()
  if fase == "aviso" then
    local c = prox_evento.cor
    if (frame // 6) % 2 == 0 then
      ui.rect(0, 0, W - 1, H - 1, c); ui.rect(2, 2, W - 3, H - 3, c)
      centro(T.aviso, 115, AMAR)
    end
    centro(nome_ev(prox_evento) .. " EM " .. (timer // 60 + 1), 135, c)
  elseif fase == "ativo" then
    local c = evento.cor
    for k = 0, 2 do ui.rect(k, k, W - 1 - k, H - 1 - k, c) end
    centro("<< " .. nome_ev(evento) .. " >>", 30, c)
    local larg = math.floor((timer / evento.dur) * 120)
    ui.rectfill(MEIO - 60, 18, MEIO - 60 + larg, 20, c)
  end
end

reset()
estado = "titulo"   -- reset() prepara a partida (e entra em contagem); no boot comecamos no titulo

function update()
  frame = frame + 1
  ui.camera()
  desenha_fundo()

  if estado == "titulo" then
    centro(T.titulo, 34, AMAR)
    centro("VOCE vs " .. T.nome2, 48, T.cor2)
    centro("direcional/WASD move   B/K tiro", 68, BRANCO)
    centro("A/J segura: LASER   Y/M escudo   R/H leque", 80, BRANCO)
    centro("L/G dash   X/L DEBUG: cancela a falha", 92, BRANCO)
    centro("START pausa   SELECT sai", 104, CINZA)
    local max_idx = desbloqueado and #ORDEM_DIF or #ORDEM_DIF - 1
    if apertou(UP) then dif_idx = math.max(1, dif_idx - 1) end
    if apertou(DOWN) then dif_idx = math.min(max_idx, dif_idx + 1) end
    for i = 1, #ORDEM_DIF do
      local d = DIFICULDADES[ORDEM_DIF[i]]
      local y = 118 + i * 14
      if d.bloqueado and not desbloqueado then
        centro("??? BLOQUEADO: venca o DIFICIL ???", y, ESCURO)
      else
        local cor = i == dif_idx and (d.bloqueado and VERM or AMAR) or CINZA
        centro(i == dif_idx and ("> " .. d.nome .. " <") or d.nome, y, cor)
      end
    end
    centro(DIFICULDADES[ORDEM_DIF[dif_idx]].desc, 200, ROXO)
    if (frame // 30) % 2 == 0 then centro("cima/baixo: dificuldade   B/K: comecar", 222, VERDE) end
    if apertou(ACAO) then reset() end
    return
  end

  if (estado == "jogo" or estado == "contagem") and ui.btnp(BTN_START, PAD1) then
    estado_ant, estado = estado, "pausa"
  elseif estado == "pausa" then
    if ui.btnp(BTN_START, PAD1) then estado = estado_ant
    elseif ui.btnp(BTN_SELECT, PAD1) then estado = "titulo"; return end
  end
  if msg_t > 0 and estado ~= "pausa" then msg_t = msg_t - 1 end
  if estado == "contagem" then
    cont_t = cont_t - 1
    if cont_t <= 0 then estado = "jogo" end
  elseif estado == "entre" then
    cont_t = cont_t - 1
    if cont_t <= 0 then rodada = rodada + 1; nova_rodada() end
  end
  if estado == "jogo" then
    atualiza_eventos()
    atualiza_player(players[1])
    atualiza_player(players[2])
  end
  if estado ~= "pausa" then atualiza_tiros() end

  if shake > 0 then
    ui.camera(math.random(-4, 4), math.random(-4, 4))
    shake = shake - 1
  end

  for _, p in ipairs(players) do
    if p.vidas > 0 and (p.hit == 0 or (frame // 3) % 2 == 0) then
      forma(T.forma, p.x, p.y, p.w, p.h, p.cor, p.dir)
    end
    if p.vidas > 0 then
      if p.escudo then ui.draw_circle(p.x + 8, p.y + 8, 13, false, AMAR, false, AMAR) end
      local carga = p.cpu and (p.carregando > 0 and (CARGA_MIN - p.carregando) or 0) or p.carga
      if carga > 0 then
        ui.circfill(p.x + (p.dir == 1 and p.w + 4 or -4), p.y + 8, 1 + carga // 8, (frame // 3) % 2 == 0 and BRANCO or p.cor)
      end
    end
  end
  for i = 1, MAX_TIROS do
    local t = tiros[i]
    if t.ativo then
      local c = t.dono == 1 and T.cor1 or T.cor2
      if t.laser then
        ui.rectfill(t.x, t.y, t.x + t.w, t.y + t.h, c); ui.rectfill(t.x, t.y + 2, t.x + t.w, t.y + t.h - 2, BRANCO)
      else forma(T.tiro_forma, t.x, t.y, 5, 5, c, t.dir) end
    end
  end
  for i = 1, MAX_PART do
    local p = parts[i]
    if p.vida > 0 then ui.rectfill(p.x, p.y, p.x + 2, p.y + 2, p.cor) end
  end

  ui.camera()
  desenha_hud()
  if estado == "jogo" then desenha_evento() end
  if msg_t > 0 then centro(msg_txt, 60, AMAR) end
  if estado == "pausa" then
    ui.rectfill(MEIO - 110, 100, MEIO + 110, 160, ESCURO); ui.rect(MEIO - 110, 100, MEIO + 110, 160, BRANCO)
    centro("PAUSA", 110, AMAR)
    centro("START continua", 128, BRANCO)
    centro("SELECT volta ao titulo", 142, CINZA)
  end
  centro(placar[1] .. " x " .. placar[2], 6, BRANCO)
  if estado == "contagem" then
    centro("RODADA " .. rodada, 105, AMAR)
    if cont_t > CONTAGEM_JA then
      ui.rect(MEIO - 14, 122, MEIO + 14, 146, BRANCO)
      centro(TXT_CONT[(cont_t - CONTAGEM_JA - 1) // CONTAGEM_PASSO + 1], 130, BRANCO)
    else
      ui.rect(MEIO - 20, 122, MEIO + 20, 146, VERDE)
      centro("JA!", 130, VERDE)
    end
  elseif estado == "entre" then
    centro(vencedor == 1 and "VOCE VENCEU A RODADA" or "CPU VENCEU A RODADA", 115, vencedor == 1 and T.cor1 or T.cor2)
  end

  if estado == "fim" then
    centro(vencedor == 1 and "VOCE VENCEU!" or "CPU VENCEU!", 115, vencedor == 1 and T.cor1 or T.cor2)
    centro("placar final " .. placar[1] .. " x " .. placar[2], 130, AMAR)
    if novo_desbloq then
      centro("NOVO NIVEL DESBLOQUEADO:", 165, VERM)
      if (frame // 8) % 2 == 0 then centro(DIFICULDADES.critico.nome, 177, VERM) end
    end
    if (frame // 30) % 2 == 0 then centro("B/K revanche   Y/M ou SELECT: titulo", 145, BRANCO) end
    if apertou(ACAO) then reset()
    elseif ui.btnp(BTN_E, PAD1) or ui.btnp(BTN_SELECT, PAD1) then
      estado = "titulo"
      if novo_desbloq then dif_idx = #ORDEM_DIF end
    end
  end
end
