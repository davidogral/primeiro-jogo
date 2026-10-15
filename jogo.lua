-- DUELO CORINGA - LUPI (480x270 @ 60fps)  -- tema da jam: FALHA NO SISTEMA
-- 1 jogador vs CPU, controle de Super Nintendo (pad 0). Todos os botoes tem mecanica:
--   SNES  mecanica                                   SDK 1.1.0 (tecla)      console (docs lupi.api.br)
--   dir   move                                       WASD                   LEFT/RIGHT/UP/DOWN
--   B     tiro                                       BTN_Z (K)              BTN_Z
--   A     segurar carrega, soltar = LASER            6 (J)                  BTN_G
--   Y     escudo (segurar; gasta energia)            BTN_E (M)              BTN_F
--   X     DEBUG: cancela a falha atual               BTN_Q (L)              BTN_X
--   L     dash com invencibilidade                   BTN_F (G)              BTN_Q
--   R     tiro em leque (3 tiros)                    BTN_G (H)              BTN_E
--   START pausa (no console: L+R juntos)             15 (so controle)       -
--   SELECT na pausa/fim: titulo (ou Y)               13 (so controle)       -
-- Eventos aleatorios (aviso -> efeito) mudam as regras. O principal: INVERSAO.
-- Para adaptar ao tema da jam: escolha/edite um tema em TEMAS e troque TEMA_ATUAL.

-- ================= CONFIG =================
local TEMA_ATUAL = "falha"    -- falha | padrao | espaco | faroeste | magia
-- PLATAFORMA: existem 2 firmwares com numeracao de botoes e formato de cor diferentes.
--   SDK lupinho 1.1.0 (simulador Docker/PC): sem BTN_X; teclado WASD + K/J/M/L/G/H; cor BGR555.
--   Console / firmware novo (docs lupi.api.br): tem BTN_X; LEFT=0..BTN_E=15; cor RGB555.
-- Detectamos pela existencia de BTN_X e nunca usamos numero cru de botao no console.
local CONSOLE = BTN_X ~= nil
local PAD1 = 0
local ACAO = "acao"          -- em menus: B, A ou START confirmam
local B_TIRO, B_LASER, B_ESCUDO, B_DEBUG, B_DASH, B_LEQUE, BTN_START, BTN_SELECT
if CONSOLE then
  B_TIRO, B_LASER, B_ESCUDO, B_DEBUG, B_DASH, B_LEQUE = BTN_Z, BTN_G, BTN_F, BTN_X, BTN_Q, BTN_E
else
  B_TIRO, B_LASER, B_ESCUDO, B_DEBUG, B_DASH, B_LEQUE = BTN_Z, 6, BTN_E, BTN_Q, BTN_F, BTN_G
  BTN_START, BTN_SELECT = 15, 13
end
-- textos de ajuda conforme a plataforma
local AJUDA = CONSOLE and {
  "direcional move   B tiro", "A segura: LASER   Y escudo   R leque",
  "L dash   X DEBUG: cancela a falha", "L+R juntos: pausa", "B: comecar", "B revanche   Y: titulo",
  "L+R ou B continua", "Y volta ao titulo",
} or {
  "direcional/WASD move   B/K tiro", "A/J segura: LASER   Y/M escudo   R/H leque",
  "L/G dash   X/L DEBUG: cancela a falha", "START pausa   SELECT sai", "B/K: comecar",
  "B/K revanche   Y/M ou SELECT: titulo", "START ou B/K continua", "Y/M ou SELECT: titulo",
}
local VIDAS = 3
local VEL, VEL_TIRO, RECARGA = 3, 6, 18
local AVISO_FRAMES = 90                       -- 1.5s de aviso
local INTERVALO_MIN, INTERVALO_MAX = 360, 720 -- 6s a 12s entre eventos
local RODADAS_PARA_VENCER = 2                 -- melhor de 3
local CONTAGEM_PASSO, CONTAGEM_JA = 45, 30    -- frames de cada "3, 2, 1" e do "JA!"
local PAUSA_RODADA = 120                      -- frames mostrando quem venceu a rodada
local FIM_FRAMES = 90                         -- explosao final antes da tela de GAME OVER / VITORIA
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
local PAL = { 0x0000, 0x7FFF, 0x001F, 0x7C00, 0x03FF, 0x294A, 0x7C1F, 0x03E0, 0x0C63, 0x01BF, 0x5000 }
for i = 1, #PAL do
  local c = PAL[i]   -- valores escritos em BGR555 (SDK); no console troca R<->B (RGB555)
  if CONSOLE then c = ((c & 31) << 10) | (c & 0x3E0) | ((c >> 10) & 31) end
  ui.palset(i - 1, c)
end
local PRETO, BRANCO, VERM, AZUL, AMAR, CINZA, ROXO, VERDE, ESCURO, LARANJA, AZUL_BSOD = 0,1,2,3,4,5,6,7,8,9,10

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
-- estatisticas da partida (aparecem no GAME OVER / VITORIA)
local est_tiros, est_acertos, est_falhas, est_patches, est_frames = 0, 0, 0, 0, 0
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
  if b == ACAO then return apertou(B_TIRO) or apertou(B_LASER) or apertou(BTN_START) end
  return b ~= nil and ui.btnp(b, PAD1) and true or false
end
local function segurando(b) return b ~= nil and ui.btn(b, PAD1) and true or false end
-- START no SDK; no console (sem START) L+R juntos
local function apertou_pausa()
  return apertou(BTN_START) or (segurando(B_DASH) and segurando(B_LEQUE) and (apertou(B_DASH) or apertou(B_LEQUE)))
end
local function volta_titulo() return apertou(B_ESCUDO) or apertou(BTN_SELECT) end
-- contorno de circulo: ui.circ no console, ui.draw_circle no SDK 1.1.0
local function circ(x, y, r, c)
  if ui.circ then ui.circ(x, y, r, c) else ui.draw_circle(x, y, r, false, c, true, c) end
end
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
  est_tiros, est_acertos, est_falhas, est_patches, est_frames = 0, 0, 0, 0, 0
  nova_rodada()
end

local function atualiza_eventos()
  timer = timer - 1
  if timer > 0 then return end
  if fase == "normal" then
    fase, timer = "aviso", AVISO_FRAMES
  elseif fase == "aviso" then
    evento, fase, timer = prox_evento, "ativo", prox_evento.dur
    shake, est_falhas = 10, est_falhas + 1
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
      if not p.cpu then est_tiros = est_tiros + 1 end
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
  if not p.cpu then est_patches = est_patches + 1 end
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
        if t.dono == 1 then est_acertos = est_acertos + 1 end
        ajusta_ia(alvo.cpu)
        explode(alvo.x + 8, alvo.y + 8, alvo.cor, 12)
        if alvo.vidas <= 0 then
          explode(alvo.x + 8, alvo.y + 8, BRANCO, 25)
          placar[t.dono] = placar[t.dono] + 1
          vencedor, shake = t.dono, 25
          if placar[t.dono] >= RODADAS_PARA_VENCER then
            estado, cont_t = "fim", FIM_FRAMES
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

-- ================= GAME OVER (tela azul) / VITORIA (antivirus) / BOOT =================
local term, term_cor = {}, {}      -- linhas do terminal: montadas 1x quando a partida acaba
local go_t, go_pronto = 0, 0
local BOOT = { "LUPI BIOS v1.1.0", "CPU ESP32-S3 @ 240MHz ............. OK", "Coprocessador RP2350 .............. OK",
  "Controle SNES (pad 0) ............. OK", "Varrendo setores .................. AMEACA PERSISTENTE",
  "Restaurando ponto de restauracao .. OK", "Carregando " .. T.titulo .. " ..." }
local BOOT_COR = { BRANCO, CINZA, CINZA, CINZA, VERM, CINZA, VERDE }
local BOOT_PASSO = 14

local function linha(i, txt, cor) term[i], term_cor[i] = txt, cor end

local function prepara_fim(venceu)
  for i = #term, 1, -1 do term[i], term_cor[i] = nil, nil end
  go_t, go_pronto = 0, 0
  local seg = est_frames // 60
  local prec = est_tiros > 0 and math.floor(100 * est_acertos / est_tiros) or 0
  local i = 1
  if venceu then
    estado = "vitoria"
    linha(1, "> ANTIVIRUS LUPI v1.1.0", VERDE)
    linha(2, "> varrendo memoria ............ 100%", VERDE)
    linha(3, "> AMEACA ENCONTRADA: " .. T.nome2, VERM)
    linha(4, "> movendo para quarentena ..... OK", VERDE)
    linha(5, "> integridade do sistema ...... 100%", VERDE)
    linha(6, "", VERDE)
    i = 7
  else
    estado = "gameover"
    linha(1, "Seu sistema encontrou um problema e precisa", BRANCO)
    linha(2, "ser reiniciado. " .. T.nome2 .. " assumiu o controle.", BRANCO)
    linha(3, "", BRANCO)
    linha(4, "CODIGO DE PARADA: FALHA_NO_SISTEMA", AMAR)
    linha(5, string.format("ENDERECO: 0x%08X", (est_frames * 2654435761 + est_tiros) % 4294967296), AMAR)
    linha(6, "", BRANCO)
    i = 7
  end
  linha(i, "dificuldade: " .. dif.curto .. "   rodadas: " .. placar[1] .. " x " .. placar[2], BRANCO)
  linha(i + 1, "tiros: " .. est_tiros .. "   acertos: " .. est_acertos .. "   precisao: " .. prec .. "%", BRANCO)
  linha(i + 2, string.format("falhas sofridas: %d   patches: %d   tempo: %02d:%02d",
    est_falhas, est_patches, seg // 60, seg % 60), BRANCO)
end

-- escreve as linhas ate n caracteres (efeito maquina de escrever); true quando tudo apareceu
local function desenha_term(x, y, dy, n)
  for i = 1, #term do
    if n <= 0 then return false end
    local l = term[i]
    ui.print(n >= #l and l or string.sub(l, 1, n), x, y + (i - 1) * dy, term_cor[i])
    n = n - #l - 4
  end
  return true
end

local function glitch_linhas(chance, c1, c2)
  if math.random() < chance then
    for i = 1, math.random(1, 3) do
      local gy = math.random(0, H - 3)
      ui.rectfill(0, gy, W, gy + math.random(1, 2), math.random(0, 1) == 0 and c1 or c2)
    end
  end
end

local function desenha_gameover()
  go_t = go_t + 1
  local t = go_t
  if t < 50 then                     -- tubo CRT desligando: tela vira linha, linha vira ponto
    ui.cls(PRETO)
    if t < 25 then
      local h = math.floor((H / 2) * (1 - t / 25)) + 1
      ui.rectfill(0, H / 2 - h, W, H / 2 + h, t < 5 and BRANCO or CINZA)
      ui.rectfill(0, H / 2 - 1, W, H / 2 + 1, BRANCO)
    elseif t < 40 then
      local w = math.floor((W / 2) * (1 - (t - 25) / 15)) + 1
      ui.rectfill(MEIO - w, H / 2 - 1, MEIO + w, H / 2 + 1, BRANCO)
    else
      ui.circfill(MEIO, H / 2, 3 - (t - 40) // 4, BRANCO)
    end
    return
  end
  ui.cls(AZUL_BSOD)                  -- tela azul da morte
  ui.rectfill(40, 26, 47, 33, BRANCO); ui.rectfill(40, 50, 47, 57, BRANCO)
  ui.clip(58, 10, 18, 66)
  for r = 26, 28 do circ(88, 42, r, BRANCO) end
  ui.clip()
  local pronto = desenha_term(40, 86, 12, (t - 60) * 3)
  if pronto then
    if go_pronto == 0 then go_pronto = t end
    local pct = math.min(100, t - go_pronto)
    ui.print("coletando dados do erro... " .. pct .. "% concluido", 40, 86 + 10 * 12, BRANCO)
    if pct >= 100 and (t // 30) % 2 == 0 then ui.print("B: reiniciar o sistema", 40, 86 + 12 * 12, AMAR) end
  end
  glitch_linhas(0.04, ROXO, AZUL)
  if apertou(ACAO) then
    if go_pronto > 0 and t - go_pronto >= 100 then estado, go_t = "boot", 0
    else go_t, go_pronto = 5000, 4900 end
  end
end

local function desenha_boot()
  go_t = go_t + 1
  ui.cls(PRETO)
  local n = math.min(#BOOT, go_t // BOOT_PASSO)
  for i = 1, n do ui.print(BOOT[i], 16, 16 + (i - 1) * 14, BOOT_COR[i]) end
  if (go_t // 15) % 2 == 0 then ui.rectfill(16, 16 + n * 14, 21, 24 + n * 14, BRANCO) end
  if go_t > #BOOT * BOOT_PASSO + 45 or (go_t > 10 and apertou(ACAO)) then estado = "titulo" end
end

local function desenha_vitoria()
  go_t = go_t + 1
  local t = go_t
  ui.cls(PRETO)
  local pronto = desenha_term(40, 30, 12, t * 2)
  if pronto then
    if go_pronto == 0 then go_pronto = t; shake = 0 end
    local c = (t // 10) % 2 == 0 and VERDE or BRANCO
    ui.rect(MEIO - 90, 156, MEIO + 90, 184, c); ui.rect(MEIO - 88, 158, MEIO + 88, 182, c)
    centro("SISTEMA RESTAURADO", 166, VERDE)
    if ORDEM_DIF[dif_idx] == "critico" then
      centro("VOCE VENCEU O IMPOSSIVEL", 196, (t // 6) % 2 == 0 and AMAR or LARANJA)
    elseif novo_desbloq then
      centro("...mas algo pior despertou:", 194, VERM)
      if (t // 8) % 2 == 0 then centro(DIFICULDADES.critico.nome .. " DESBLOQUEADO", 206, VERM) end
      glitch_linhas(0.2, VERM, ROXO)
    end
    if (t // 30) % 2 == 0 then centro(AJUDA[6], 240, BRANCO) end
    if apertou(ACAO) then reset()
    elseif volta_titulo() then
      estado = "titulo"
      if novo_desbloq then dif_idx = #ORDEM_DIF end
    end
  elseif apertou(ACAO) then go_t = 3000 end
end

reset()
estado = "titulo"   -- reset() prepara a partida (e entra em contagem); no boot comecamos no titulo

function update()
  frame = frame + 1
  ui.camera()
  if estado == "gameover" then desenha_gameover(); return end
  if estado == "boot" then desenha_boot(); return end
  if estado == "vitoria" then desenha_vitoria(); return end
  desenha_fundo()

  if estado == "titulo" then
    centro(T.titulo, 34, AMAR)
    centro("VOCE vs " .. T.nome2, 48, T.cor2)
    centro(AJUDA[1], 68, BRANCO)
    centro(AJUDA[2], 80, BRANCO)
    centro(AJUDA[3], 92, BRANCO)
    centro(AJUDA[4], 104, CINZA)
    local max_idx = desbloqueado and #ORDEM_DIF or #ORDEM_DIF - 1
    if apertou(UP) then dif_idx = math.max(1, dif_idx - 1) end
    if apertou(DOWN) then dif_idx = math.min(max_idx, dif_idx + 1) end
    for i = 1, #ORDEM_DIF do
      local d = DIFICULDADES[ORDEM_DIF[i]]
      local y = 118 + i * 14
      if d.bloqueado and not desbloqueado then
        centro("??? BLOQUEADO: venca o DIFICIL ???", y, CINZA)
      else
        local cor = i == dif_idx and (d.bloqueado and VERM or AMAR) or CINZA
        centro(i == dif_idx and ("> " .. d.nome .. " <") or d.nome, y, cor)
      end
    end
    centro(DIFICULDADES[ORDEM_DIF[dif_idx]].desc, 200, ROXO)
    if (frame // 30) % 2 == 0 then centro("cima/baixo: dificuldade   " .. AJUDA[5], 222, VERDE) end
    if apertou(ACAO) then reset() end
    return
  end

  if (estado == "jogo" or estado == "contagem") and apertou_pausa() then
    estado_ant, estado = estado, "pausa"
  elseif estado == "pausa" then
    if apertou_pausa() or apertou(B_TIRO) then estado = estado_ant
    elseif volta_titulo() then estado = "titulo"; return end
  end
  if msg_t > 0 and estado ~= "pausa" then msg_t = msg_t - 1 end
  if estado == "contagem" then
    cont_t = cont_t - 1
    if cont_t <= 0 then estado = "jogo" end
  elseif estado == "fim" then
    cont_t = cont_t - 1
    if cont_t <= 0 then prepara_fim(vencedor == 1) end
  elseif estado == "entre" then
    cont_t = cont_t - 1
    if cont_t <= 0 then rodada = rodada + 1; nova_rodada() end
  end
  if estado == "jogo" then
    est_frames = est_frames + 1
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
      if p.escudo then circ(p.x + 8, p.y + 8, 13, AMAR) end
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
    centro(AJUDA[7], 128, BRANCO)
    centro(AJUDA[8], 142, CINZA)
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
  end
end
