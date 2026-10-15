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
AJUDA[9] = "cima/baixo: dificuldade   " .. AJUDA[5]
AJUDA[10] = CONSOLE and "Y: tutorial   X: historia" or "Y/M: tutorial   X/L: historia"
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
local DASH_T, DASH_VEL, DASH_CD = 12, 10, 75   -- dash: frames, velocidade inicial (freia ate 40%), recarga
local RASTRO_N, RASTRO_VIDA = 12, 24           -- ecos da nave deixados pelo dash
local LEQUE_CD, LEQUE_VY = 90, 1.5
local DEBUG_CARGAS = 1                        -- DEBUGs do jogador por rodada
-- Evento CHUVA DE ASTEROIDES (sprites src/asteroides/*.png, Space Shooter Redux por Kenney, CC0)
local MAX_AST, AST_SPAWN = 10, 9              -- pool e frames entre asteroides
local AST_TIPOS = {                           -- tam = lado do PNG (console nao informa), raio = hitbox
  { nome = "meteorGrey_med1",   tam = 43, raio = 16, vel = 1.6, hp = 3 },
  { nome = "meteorGrey_small1", tam = 28, raio = 11, vel = 2.3, hp = 2 },
  { nome = "meteorGrey_tiny1",  tam = 18, raio = 7,  vel = 3.0, hp = 1 },
}
local AST_ESCUDO = 30                         -- energia de escudo gasta ao bloquear um asteroide

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
for _, d in pairs(DIFICULDADES) do d.sel, d.desbloq = "> " .. d.nome .. " <", d.nome .. " DESBLOQUEADO" end
local DIF_INICIAL = 2
local AJUSTE = 0.15          -- adaptativo: +-15% por vida perdida a favor de quem perde
local CONFUSAO = 30          -- frames que a CPU anda errado no inicio do "inverte"
local ALINHADO = 10          -- px de diferenca no Y para a CPU considerar que esta na mira

-- ================= PALETA =================
-- Cores dos sprites: o codec gera palette.lua (Palette) e os PNGs usam os indices 0..#Palette-1.
-- As cores do jogo ficam DEPOIS delas para nao estragar os sprites (limite do console: 256 cores).
pcall(require, "palette")
local SPR_PAL = Palette or {}
local BASE = #SPR_PAL
local PAL = { 0x0000, 0x7FFF, 0x001F, 0x7C00, 0x03FF, 0x294A, 0x7C1F, 0x03E0, 0x0C63, 0x01BF, 0x5000, 0x1972, 0x42DB }
-- Cores em BGR555, o mesmo formato que o lupi-codec gera para palette.lua (vale no SDK e no console).
-- Reaplicada TODO frame, como o primeiro-jogo oficial faz (o console pode resetar a paleta apos o load).
local function aplica_paleta()
  for i = 1, #SPR_PAL do ui.palset(i - 1, SPR_PAL[i]) end
  for i = 2, #PAL do ui.palset(BASE + i - 1, PAL[i]) end
end
aplica_paleta()
local PRETO = 0   -- indice 0 = transparente (fundo preto)
local BRANCO, VERM, AZUL, AMAR, CINZA, ROXO, VERDE, ESCURO, LARANJA, AZUL_BSOD, MARROM, BEGE =
  BASE + 1, BASE + 2, BASE + 3, BASE + 4, BASE + 5, BASE + 6, BASE + 7, BASE + 8, BASE + 9, BASE + 10, BASE + 11, BASE + 12

-- Sprites das naves (src/naves/*.png, "Cozy Space Ships" por Bramble & Byte, CC-BY 4.0).
-- Esperado: PNG girado 90 graus horario (apontando para a DIREITA); a CPU e espelhada no codigo.
-- Sem o PNG, cai na nave geometrica.
pcall(require, "sprites")
local NAVE_SPR, NAVE_TAM = {}, 24   -- sparrow 1x = 24x24
if Sprites and Sprites.naves then NAVE_SPR[1], NAVE_SPR[2] = Sprites.naves["sparrow-cream"], Sprites.naves["sparrow-slate"] end
-- Projeteis (Cozy Space Ships, CC-BY 4.0): plasma 4 quadros de 10x10 lado a lado (1x),
-- desenhado com clip para mostrar 1 quadro; laser vertical 6x18 (2x) na parede do tutorial.
local PLASMA, LASER_V = {}, nil
local PLASMA_Q = 10
-- No console o plasma animado (clip + spr por tiro, todo frame) pesava e travava com muitos tiros
-- (leque, tutorial): la o tiro e desenhado em codigo, sem clip. A animacao por sprite fica so no SDK.
if Sprites and Sprites.projeteis then
  if not CONSOLE then PLASMA[1], PLASMA[2] = Sprites.projeteis["plasma-teal-4f"], Sprites.projeteis["plasma-rose-4f"] end
  LASER_V = Sprites.projeteis["laser-rose"]
end
local cam_dx, cam_dy = 0, 0   -- deslocamento do shake (o clip e em coordenada de tela)
local escala_tiros = 1        -- camera lenta dos tiros do virus (usada no tutorial do dash)
local AST_SPR = {}   -- sem o PNG, o asteroide vira um circulo
if Sprites and Sprites.asteroides then
  for i = 1, #AST_TIPOS do AST_SPR[i] = Sprites.asteroides[AST_TIPOS[i].nome] end
end

local W, H = 480, 270
local MEIO = W / 2

-- ================= EVENTOS =================
local EVENTOS = {
  inverte = { nome = "INVERTIDO", cor = ROXO,    dur = 300, inv = true },
  turbo   = { nome = "TURBO",     cor = LARANJA, dur = 240, vel = 2 },
  lama    = { nome = "LENTO",     cor = CINZA,   dur = 240, vel = 0.4 },
  rajada  = { nome = "RAJADA",    cor = VERDE,   dur = 240, rec = 0.3, tiro = 1.5 },
  chuva   = { nome = "CHUVA DE ASTEROIDES", cor = LARANJA, dur = 360, chuva = true },
}
for k, e in pairs(EVENTOS) do e.id = k end

-- ================= TEMAS =================
local TEMAS = {
  falha = {
    titulo = "FALHA NO SISTEMA", nome1 = "NAVE", nome2 = "VIRUS.EXE",
    cor1 = VERDE, cor2 = VERM, fundo_cor = PRETO, fundo = "estrelas", glitch = true,
    forma = "nave", tiro_forma = "quad", aviso = "ERRO CRITICO DETECTADO",
    vitoria = " VENCEU!", eventos = { "inverte", "inverte", "turbo", "lama", "rajada", "chuva", "chuva" },
    nomes = { inverte = "CONTROLES CORROMPIDOS", turbo = "OVERCLOCK", lama = "LAG", rajada = "BUFFER OVERFLOW",
              chuva = "CHUVA DE ASTEROIDES" },
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
    vitoria = " DOMINA A ORBITA!", eventos = { "inverte", "inverte", "lama", "turbo", "chuva" },
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

-- Textos montados 1x no load (concatenar dentro do update gera lixo para o GC todo frame)
for k, e in pairs(EVENTOS) do
  local nome = (T.nomes and T.nomes[k]) or e.nome
  e.txt_ativo = "<< " .. nome .. " >>"
  e.txt_aviso = { nome .. " EM 1", nome .. " EM 2", nome .. " EM 3" }
end
local TXT_PLACAR, TXT_FINAL = {}, {}
for a = 0, 2 do for b = 0, 2 do
  TXT_PLACAR[a * 3 + b] = a .. " x " .. b
  TXT_FINAL[a * 3 + b] = "placar final " .. a .. " x " .. b
end end
local TXT_RODADA = { "RODADA 1", "RODADA 2", "RODADA 3" }
local TXT_VS = "VOCE vs " .. T.nome2

-- ================= DESEMPENHO =================
-- GC geracional: o lixo de vida curta e limpo em passos pequenos (sem engasgo no ESP32).
pcall(collectgarbage, "generational")

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

local MAX_TIROS, MAX_PART = 24, 40   -- dimensionado pelo uso real (2 naves x ~10 tiros vivos)
local tiros, parts = {}, {}
for i = 1, MAX_TIROS do tiros[i] = { ativo = false, x = 0, y = 0, dir = 0, dono = 0, v = 0, vy = 0, w = 5, h = 5, laser = false } end
for i = 1, MAX_PART do parts[i] = { vida = 0, x = 0, y = 0, vx = 0, vy = 0, cor = 0 } end
local asts = {}
for i = 1, MAX_AST do asts[i] = { ativo = false, x = 0, y = 0, vx = 0, vy = 0, tipo = 1, hp = 0 } end

local estrelas = {}
for i = 1, 40 do estrelas[i] = { x = math.random(0, W), y = math.random(0, H), v = math.random(1, 3) } end

-- ================= UTIL =================
-- "Recem-apertado" calculado aqui com ui.btn (agora e nao no frame anterior). Nao usamos ui.btnp:
-- no console ele repete enquanto segura (estilo PICO-8), o que despausava sozinho apos ~1s.
local BOTOES, b_ant, b_now = {}, {}, {}
local function add_botao(b) if b ~= nil then BOTOES[#BOTOES + 1] = b end end
add_botao(UP); add_botao(DOWN); add_botao(LEFT); add_botao(RIGHT)
add_botao(B_TIRO); add_botao(B_LASER); add_botao(B_ESCUDO); add_botao(B_DEBUG); add_botao(B_DASH); add_botao(B_LEQUE)
add_botao(BTN_START); add_botao(BTN_SELECT)
local function le_botoes()   -- 1x por frame, no inicio do update
  for i = 1, #BOTOES do
    local b = BOTOES[i]
    b_ant[b] = b_now[b] or false
    b_now[b] = ui.btn(b, PAD1) and true or false
  end
end
local function apertou(b)
  if b == ACAO then return apertou(B_TIRO) or apertou(B_LASER) or apertou(BTN_START) end
  return b ~= nil and b_now[b] == true and not b_ant[b]
end
local function segurando(b) return b ~= nil and b_now[b] == true end
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
           dash_t = 0, dash_dx = 0, dash_dy = 0, dash_cd = 0, leque_cd = 0, debug = 0,
           rastro_x = {}, rastro_y = {}, rastro_t = {}, rastro_i = 0,
           -- so a CPU usa: parametros atuais da IA e estado da decisao
           cpu = id == 2, reacao = 0, erro = 0, desvio = 0, cont = 0, alvo_y = H / 2 - 8, quer_atirar = false,
           escudo_t = 0, carregando = 0, dash_pref = 1, desv_t = 0, desv_dir = 0, debug_neg = 0, dash_neg = 0, leque_neg = 0 }
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
    p.desv_t, p.desv_dir = 0, 0
    p.debug = p.cpu and dif.debug or DEBUG_CARGAS
  end
  for i = 1, MAX_TIROS do tiros[i].ativo = false end
  for i = 1, MAX_AST do asts[i].ativo = false end
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
    -- asteroide caindo em cima: desvia para o lado (dx) ou levanta o escudo
    for i = 1, MAX_AST do
      local a = asts[i]
      if a.ativo then
        local r = AST_TIPOS[a.tipo].raio
        local cx, cy = c.x + c.w / 2, c.y + c.h / 2
        local fx = a.x + a.vx * ((cy - a.y) / a.vy)   -- onde ele cruza a altura da CPU
        if a.y < cy + r and cy - a.y < 90 and math.abs(fx - cx) < r + 12 then
          if math.random() < c.desvio then
            c.desv_t, c.desv_dir = 18, (fx > cx) and -1 or 1
            if c.x < MEIO + 20 then c.desv_dir = 1 elseif c.x > W - c.w - 20 then c.desv_dir = -1 end
          elseif not c.quebrado and math.random() < dif.escudo then
            c.escudo_t = 25
          end
          break
        end
      end
    end
  end
  local dy, diff = 0, c.alvo_y - c.y
  if diff > 2 then dy = 1 elseif diff < -2 then dy = -1 end
  if dash then dy = c.dash_pref end
  -- no "inverte" a CPU tambem fica confusa: anda errado nos primeiros CONFUSAO frames, depois compensa
  if fase == "ativo" and evento.inv and (evento.dur - timer) < CONFUSAO then dy = -dy end
  local atira = c.quer_atirar and math.abs(c.y - alvo.y) < ALINHADO
  -- dx: desvio lateral de asteroide; senao volta devagar para a posicao inicial
  local dx = 0
  if c.desv_t > 0 then c.desv_t, dx = c.desv_t - 1, c.desv_dir
  elseif c.x < W - 48 then dx = 1 elseif c.x > W - 44 then dx = -1 end
  return dx, dy, atira, c.escudo_t > 0, dash, leque, laser, false, debug
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
  return dx, dy, apertou(B_TIRO), segurando(B_ESCUDO), apertou(B_DASH), apertou(B_LEQUE),
         laser, carregando, apertou(B_DEBUG)
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

  -- L: dash na direcao segurada (diagonais valem); sem direcao = para frente. Invencivel durante.
  if p.dash_cd > 0 then p.dash_cd = p.dash_cd - 1 end
  if p.dash_neg > 0 then p.dash_neg = p.dash_neg - 1 end
  if p.leque_neg > 0 then p.leque_neg = p.leque_neg - 1 end
  if dash and (p.dash_cd > 0 or p.dash_t > 0) then p.dash_neg = 20 end   -- apertou recarregando: HUD pisca vermelho
  if dash and p.dash_cd <= 0 and p.dash_t <= 0 then
    p.dash_t, p.dash_cd = DASH_T, DASH_CD
    local ddx, ddy = dx, dy
    if ddx == 0 and ddy == 0 then ddx = p.dir end
    if ddx ~= 0 and ddy ~= 0 then ddx, ddy = ddx * 0.7071, ddy * 0.7071 end
    p.dash_dx, p.dash_dy = ddx, ddy
    explode(p.x + 8, p.y + 8, BRANCO, 4)
  end
  for k = 1, RASTRO_N do if p.rastro_t[k] and p.rastro_t[k] > 0 then p.rastro_t[k] = p.rastro_t[k] - 1 end end

  local y0 = p.y
  if p.dash_t > 0 then
    local v = DASH_VEL * (0.4 + 0.6 * p.dash_t / DASH_T)   -- arranca rapido e freia suave
    p.dash_t = p.dash_t - 1
    p.x, p.y = p.x + p.dash_dx * v, p.y + p.dash_dy * v
    p.rastro_i = p.rastro_i % RASTRO_N + 1                 -- grava um eco por frame
    p.rastro_x[p.rastro_i], p.rastro_y[p.rastro_i], p.rastro_t[p.rastro_i] = p.x, p.y, RASTRO_VIDA
    if p.dash_t % 3 == 0 then explode(p.x + 8, p.y + 8, p.cor, 1) end
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
  if leque and p.leque_cd > 0 then p.leque_neg = 20 end
  if leque and p.leque_cd <= 0 then
    atirar(p, -LEQUE_VY, false); atirar(p, 0, false); atirar(p, LEQUE_VY, false)
    p.leque_cd = math.floor(LEQUE_CD * mod("rec") * (p.cpu and dif.rec or 1))
  end
  -- A: laser
  if laser and p.laser_cd <= 0 then
    atirar(p, 0, true)
    p.laser_cd, shake = LASER_CD, 4
  end
  -- X: DEBUG (so tem efeito com falha na tela; senao o X do HUD pisca vermelho = "nada para cancelar")
  if p.debug_neg > 0 then p.debug_neg = p.debug_neg - 1 end
  if debug then
    if p.debug > 0 and fase ~= "normal" then cancela_falha(p) else p.debug_neg = 30 end
  end
end

-- Tira 1 vida de `alvo`; se zerar, `autor` (id do outro lado) ganha a rodada.
local function dano(alvo, autor)
  if alvo.escudo then alvo.escudo, alvo.quebrado, alvo.energia = false, true, 0 end
  alvo.vidas, alvo.hit, shake = alvo.vidas - 1, 45, 12
  ajusta_ia(alvo.cpu)
  explode(alvo.x + 8, alvo.y + 8, alvo.cor, 12)
  if alvo.vidas <= 0 then
    explode(alvo.x + 8, alvo.y + 8, BRANCO, 25)
    placar[autor] = placar[autor] + 1
    vencedor, shake = autor, 25
    if placar[autor] >= RODADAS_PARA_VENCER then
      estado, cont_t = "fim", FIM_FRAMES
      if autor == 1 and ORDEM_DIF[dif_idx] == "dificil" and not desbloqueado then
        desbloqueado, novo_desbloq = true, true
      end
    else estado, cont_t = "entre", PAUSA_RODADA end
  end
end

-- CHUVA DE ASTEROIDES: nascem no topo durante o evento e caem na diagonal pela tela toda.
-- Tiros quebram (hp), escudo bloqueia (gasta energia), dash atravessa, encostar tira 1 vida.
local function atualiza_asteroides()
  if estado == "jogo" and fase == "ativo" and evento.chuva and frame % AST_SPAWN == 0 then
    for i = 1, MAX_AST do
      local a = asts[i]
      if not a.ativo then
        local tp = math.random(1, #AST_TIPOS)
        local ti = AST_TIPOS[tp]
        a.ativo, a.tipo, a.hp = true, tp, ti.hp
        a.x, a.y = math.random(10, W - 10), YMIN - ti.tam
        a.vy = ti.vel * (0.8 + math.random() * 0.4)
        a.vx = (math.random() - 0.5) * 1.6
        break
      end
    end
  end
  for i = 1, MAX_AST do
    local a = asts[i]
    if a.ativo then
      local r = AST_TIPOS[a.tipo].raio
      a.x, a.y = a.x + a.vx, a.y + a.vy
      if a.y > H + 40 or a.x < -40 or a.x > W + 40 then a.ativo = false end
      -- tiros
      for j = 1, MAX_TIROS do
        local t = tiros[j]
        if a.ativo and t.ativo and math.abs(t.x + t.w / 2 - a.x) < r + t.w / 2 and math.abs(t.y + t.h / 2 - a.y) < r + t.h / 2 then
          if not t.laser then t.ativo = false end
          a.hp = a.hp - (t.laser and 99 or 1)
          if a.hp <= 0 then a.ativo = false; explode(a.x, a.y, CINZA, 8)
          else explode(t.x, t.y, BRANCO, 2) end
        end
      end
      -- naves
      for k = 1, 2 do
        local p = players[k]
        if a.ativo and estado == "jogo" and p.hit == 0 and p.dash_t == 0 then
          local dx, dy = a.x - (p.x + p.w / 2), a.y - (p.y + p.h / 2)
          if dx * dx + dy * dy < (r + 7) * (r + 7) then
            a.ativo = false
            explode(a.x, a.y, CINZA, 10)
            if p.escudo then
              p.energia = p.energia - AST_ESCUDO
              if p.energia <= 0 then p.energia, p.escudo, p.quebrado = 0, false, true end
            else
              dano(p, k == 1 and 2 or 1)
            end
          end
        end
      end
    end
  end
end

local function atualiza_tiros()
  for i = 1, MAX_TIROS do
    local t = tiros[i]
    if t.ativo then
      local e = t.dono == 2 and escala_tiros or 1
      t.x, t.y = t.x + t.dir * t.v * e, t.y + t.vy * e
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
        t.ativo = false
        if t.dono == 1 then est_acertos = est_acertos + 1 end
        dano(alvo, t.dono)
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
  for y = 24, YMAX, 12 do ui.line(MEIO, y, MEIO, y + 5, CINZA) end
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
  local pisca = (frame // 4) % 2 == 0
  ui.print("L", 108, y, BRANCO)
  ui.rectfill(116, y, 122, y + 6, (p.dash_neg > 0 and pisca) and VERM or (p.dash_cd <= 0 and VERDE or CINZA))
  ui.print("R", 130, y, BRANCO)
  ui.rectfill(138, y, 144, y + 6, (p.leque_neg > 0 and pisca) and VERM or (p.leque_cd <= 0 and VERDE or CINZA))
  local xneg = p.debug_neg > 0 and (frame // 4) % 2 == 0
  local xpronto = p.debug > 0 and fase ~= "normal"           -- ha falha para cancelar: X acende
  ui.print("X", 152, y, xneg and VERM or (xpronto and ((frame // 8) % 2 == 0 and AMAR or BRANCO) or BRANCO))
  ui.print(TXT_NUM[p.debug] or "+", 160, y, xneg and VERM or (p.debug > 0 and AMAR or CINZA))
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
    centro(prox_evento.txt_aviso[timer // 60 + 1] or "", 135, c)
  elseif fase == "ativo" then
    local c = evento.cor
    for k = 0, 2 do ui.rect(k, k, W - 1 - k, H - 1 - k, c) end
    centro(evento.txt_ativo, 30, c)
    local larg = math.floor((timer / evento.dur) * 120)
    ui.rectfill(MEIO - 60, 18, MEIO - 60 + larg, 20, c)
  end
end

-- Tutorial e historia ficam em blocos do...end para nao estourar o limite de 200 locais do Lua;
-- so as funcoes usadas fora sao exportadas. PROG guarda o que ja foi visto (vale ate desligar).
local tut_comeca, tut_fim, atualiza_tutorial, desenha_tutorial, historia_comeca, atualiza_historia
local PROG = { tut = false, hist = false }

-- ================= TUTORIAL (estilo fase 1-1: sem texto, aprende fazendo) =================
do
-- Cada obstaculo so se resolve com a mecanica que ensina. A unica "lingua" e um controle de SNES
-- desenhado embaixo com o botao certo pulsando. Errar nao pune: a nave pisca e o obstaculo repete.
-- Roda sozinho na 1a partida apos ligar; no titulo, Y repete; pausa (START / L+R) pula.
local TUT_PASSOS = { "mover", "tiro", "escudo", "dash", "leque", "laser", "debug" }
local TUT_BOTAO = { mover = "dpad", tiro = "B", escudo = "Y", dash = "L", leque = "R", laser = "A", debug = "X" }
local TUT_PAREDES = 2          -- paredes que precisa atravessar sem ser atingido (escudo e dash)
local TUT_JANELA = 12          -- frames para matar o trio do leque antes de ele se regenerar
local tut_i, tut_t, tut_cont, tut_pausa, tut_janela = 1, 0, 0, 0, 0
local tut_wx, tut_wv, tut_parede_on, tut_hit = 0, 0, false, false
local MAX_ALVOS = 6
local alvos = {}               -- tipo: 1 pacote de dados, 2 bug, 3 bloco blindado
for i = 1, MAX_ALVOS do alvos[i] = { ativo = false, x = 0, y = 0, w = 0, h = 0, tipo = 1, by = 0, dx = 0 } end
local TUT_PACOTES = { 70, 40, 70, 210, MEIO - 50, 128 }   -- x, y dos pacotes do passo "mover"

local function tut_alvo(tipo, x, y, w, h)
  for i = 1, MAX_ALVOS do
    local a = alvos[i]
    if not a.ativo then
      a.ativo, a.tipo, a.x, a.y, a.w, a.h, a.by, a.dx = true, tipo, x, y, w, h, y, 0
      return a
    end
  end
end

local function tut_limpa()
  for i = 1, MAX_ALVOS do alvos[i].ativo = false end
  for i = 1, MAX_TIROS do tiros[i].ativo = false end
  tut_parede_on = false
end

local function tut_vivos()
  local n = 0
  for i = 1, MAX_ALVOS do if alvos[i].ativo then n = n + 1 end end
  return n
end

-- trio do leque: fica sempre ~200px a frente da nave (distancia em que o leque abre +-50px)
local function tut_trio()
  local p = players[1]
  local cy = ui.mid(YMIN + 52, p.y + p.h / 2, YMAX - 36)
  for k = -1, 1 do
    local a = tut_alvo(2, 0, cy + k * 50 - 9, 18, 18)
    a.dx = 200
  end
  tut_janela = 0
end

local function tut_parede(laser)
  for k = 0, 10 do
    for i = 1, MAX_TIROS do
      local t = tiros[i]
      if not t.ativo then
        t.ativo, t.dono, t.dir, t.vy, t.laser = true, 2, -1, 0, laser
        t.w, t.h = laser and 8 or 6, laser and 18 or 6
        t.v = laser and 3.5 or 2.2
        t.x, t.y = W - 20, YMIN + k * 20
        break
      end
    end
  end
  tut_wx, tut_wv, tut_parede_on, tut_hit = W - 20, laser and 3.5 or 2.2, true, false
end

local function tut_inicia_passo()
  local p, passo = players[1], TUT_PASSOS[tut_i]
  tut_limpa()
  tut_t, tut_cont = 0, 0
  p.energia, p.quebrado, p.laser_cd, p.dash_cd, p.leque_cd = ESC_MAX, false, 0, 0, 0
  if passo == "mover" then
    tut_alvo(1, TUT_PACOTES[1], TUT_PACOTES[2], 10, 10)
  elseif passo == "tiro" then
    tut_alvo(2, W - 110, 60, 16, 16); tut_alvo(2, W - 170, H / 2 - 8, 16, 16); tut_alvo(2, W - 110, 196, 16, 16)
  elseif passo == "leque" then
    tut_trio()
  elseif passo == "laser" then
    tut_alvo(3, W - 140, H / 2 - 16, 30, 30)
  elseif passo == "debug" then
    p.debug = 1
    fase, evento, timer = "ativo", EVENTOS.inverte, 99999
    shake = 10
    tut_alvo(1, TUT_PACOTES[1], TUT_PACOTES[2], 10, 10)
  end
end

tut_comeca = function()
  tut_i, tut_pausa = 1, 0
  local p = players[1]
  p.x, p.y, p.hit = 30, H / 2 - 8, 0
  estado = "tutorial"
  tut_inicia_passo()
end

tut_fim = function()
  tut_limpa()
  escala_tiros = 1
  PROG.tut = true
  fase, evento, msg_t = "normal", nil, 0
  est_tiros, est_acertos, est_falhas, est_patches, est_frames = 0, 0, 0, 0, 0
  explode(players[2].x + 8, players[2].y + 8, T.cor2, 20)   -- VIRUS.EXE "materializa"
  nova_rodada()
end

local function tut_sucesso()
  local p = players[1]
  escala_tiros = 1
  explode(p.x + 8, p.y + 8, VERDE, 16)
  tut_pausa = 50
  tut_limpa()
end

atualiza_tutorial = function()
  local p, passo = players[1], TUT_PASSOS[tut_i]
  msg_t = 0
  atualiza_player(p)
  tut_t = tut_t + 1

  if tut_pausa > 0 then
    tut_pausa = tut_pausa - 1
    if tut_pausa == 0 then
      if passo == "debug" then fase, evento = "normal", nil end
      tut_i = tut_i + 1
      if tut_i > #TUT_PASSOS then tut_fim() else tut_inicia_passo() end
    end
    return
  end

  -- tiros do virus x nave: dash atravessa, escudo bloqueia (menos laser), senao so pisca
  for i = 1, MAX_TIROS do
    local t = tiros[i]
    if t.ativo and t.dono == 2 and t.x < p.x + p.w and t.x + t.w > p.x and t.y < p.y + p.h and t.y + t.h > p.y then
      t.ativo = false
      if p.dash_t > 0 then explode(t.x, t.y, BRANCO, 1)
      elseif p.escudo and not t.laser then explode(t.x, t.y, AMAR, 2)
      elseif p.hit == 0 then p.hit, shake, tut_hit = 30, 6, true end
    end
  end

  -- tiros da nave x alvos
  for i = 1, MAX_TIROS do
    local t = tiros[i]
    if t.ativo and t.dono == 1 then
      for j = 1, MAX_ALVOS do
        local a = alvos[j]
        if a.ativo and a.tipo ~= 1 and t.x < a.x + a.w and t.x + t.w > a.x and t.y < a.y + a.h and t.y + t.h > a.y then
          if a.tipo == 3 and not t.laser then
            t.ativo = false; explode(t.x, t.y, AMAR, 3)          -- blindado: tiro comum ricocheteia
          else
            if not t.laser then t.ativo = false end
            a.ativo = false
            explode(a.x + a.w / 2, a.y + a.h / 2, a.tipo == 3 and BRANCO or VERM, a.tipo == 3 and 24 or 10)
            if passo == "leque" and tut_janela == 0 then tut_janela = TUT_JANELA end
          end
        end
      end
    end
  end

  -- alvos: pacotes coletados pela nave, bugs balancando
  for j = 1, MAX_ALVOS do
    local a = alvos[j]
    if a.ativo then
      if a.tipo == 2 then
        a.y = a.by + math.sin(frame * 0.05 + j) * (passo == "leque" and 0 or 10)
        if a.dx > 0 then a.x = ui.mid(MEIO + 4, p.x + p.w + a.dx, W - a.w - 2) end
      elseif a.tipo == 1 and a.x < p.x + p.w and a.x + a.w > p.x and a.y < p.y + p.h and a.y + a.h > p.y then
        a.ativo = false
        explode(a.x + 5, a.y + 5, VERDE, 8)
        tut_cont = tut_cont + 1
        if passo == "mover" and tut_cont < 3 then
          tut_alvo(1, TUT_PACOTES[tut_cont * 2 + 1], TUT_PACOTES[tut_cont * 2 + 2], 10, 10)
        elseif passo == "debug" then
          tut_alvo(1, math.random(20, MEIO - 40), math.random(YMIN + 10, YMAX - 10), 10, 10)
        end
      end
    end
  end

  -- regras de cada passo
  if passo == "mover" then
    if tut_cont >= 3 then tut_sucesso() end
  elseif passo == "tiro" or passo == "laser" then
    if tut_vivos() == 0 then tut_sucesso() end
  elseif passo == "leque" then
    if tut_janela > 0 then
      tut_janela = tut_janela - 1
      if tut_vivos() == 0 then tut_sucesso()
      elseif tut_janela == 0 then           -- nao matou o trio junto: ele se regenera
        for j = 1, MAX_ALVOS do
          local a = alvos[j]
          if a.ativo then explode(a.x + 9, a.y + 9, ROXO, 6); a.ativo = false end
        end
        shake = 4
        tut_trio()
      end
    end
  elseif passo == "escudo" or passo == "dash" then
    escala_tiros = 1
    if passo == "dash" and tut_parede_on and p.dash_t == 0 and not tut_hit then
      local dist = tut_wx - (p.x + p.w)
      if dist > -4 and dist < 70 then escala_tiros = 0.15 end   -- camera lenta: a hora e agora
    end
    if tut_parede_on then
      tut_wx = tut_wx - tut_wv * escala_tiros
      if tut_wx < p.x - 12 then
        tut_parede_on, tut_t = false, 0
        if not tut_hit then
          tut_cont = tut_cont + 1
          explode(p.x + 8, p.y + 8, VERDE, 6)
          if tut_cont >= TUT_PAREDES then tut_sucesso() end
        end
      end
    elseif tut_t > 60 then
      tut_parede(passo == "dash")
    end
  elseif passo == "debug" then
    if fase == "normal" then tut_sucesso() end
  end
end

-- controle de SNES desenhado; o botao `hl` pulsa nas cores do Super Famicom
local ctl_hl, ctl_pisca = nil, false
local function cor(nome, normal) return (ctl_hl == nome and ctl_pisca) and BRANCO or normal end
local function desenha_controle(hl)
  local cx, cy = MEIO, 255
  local pisca = (frame // 6) % 2 == 0
  ctl_hl, ctl_pisca = hl, pisca
  ui.rectfill(cx - 26, cy - 15, cx - 6, cy - 12, cor("L", CINZA))
  ui.rectfill(cx + 6, cy - 15, cx + 26, cy - 12, cor("R", CINZA))
  ui.rectfill(cx - 30, cy - 11, cx + 30, cy + 11, ESCURO)
  ui.circfill(cx - 30, cy, 11, ESCURO); ui.circfill(cx + 30, cy, 11, ESCURO)
  local dp = cor("dpad", CINZA)
  ui.rectfill(cx - 39, cy - 2, cx - 27, cy + 2, dp); ui.rectfill(cx - 35, cy - 6, cx - 31, cy + 6, dp)
  local bx = cx + 33
  ui.circfill(bx, cy - 6, 3, cor("X", AZUL)); ui.circfill(bx, cy + 6, 3, cor("B", AMAR))
  ui.circfill(bx - 6, cy, 3, cor("Y", VERDE)); ui.circfill(bx + 6, cy, 3, cor("A", VERM))
  if pisca then
    if hl == "X" then circ(bx, cy - 6, 6, BRANCO) elseif hl == "B" then circ(bx, cy + 6, 6, BRANCO)
    elseif hl == "Y" then circ(bx - 6, cy, 6, BRANCO) elseif hl == "A" then circ(bx + 6, cy, 6, BRANCO)
    elseif hl == "dpad" then circ(cx - 33, cy, 9, BRANCO)
    elseif hl == "L" then ui.rect(cx - 28, cy - 17, cx - 4, cy - 10, BRANCO)
    elseif hl == "R" then ui.rect(cx + 4, cy - 17, cx + 28, cy - 10, BRANCO) end
  end
  -- segurar: barra embaixo enche enquanto o botao esta pressionado (A carrega, Y escudo)
  local p = players[1]
  if hl == "A" and p.carga > 0 then ui.rectfill(cx - 20, cy + 13, cx - 20 + math.floor(40 * p.carga / CARGA_MAX), cy + 14, p.carga >= CARGA_MIN and BRANCO or AMAR) end
  if hl == "Y" and p.escudo then ui.rectfill(cx - 20, cy + 13, cx - 20 + math.floor(40 * p.energia / ESC_MAX), cy + 14, AMAR) end
end

desenha_tutorial = function()
  local p, passo = players[1], TUT_PASSOS[tut_i]
  -- progresso: um ponto por passo
  for i = 1, #TUT_PASSOS do
    local x = MEIO - (#TUT_PASSOS - 1) * 7 + (i - 1) * 14
    if i < tut_i or (i == tut_i and tut_pausa > 0) then ui.circfill(x, 10, 3, VERDE)
    elseif i == tut_i then circ(x, 10, 3, (frame // 10) % 2 == 0 and BRANCO or CINZA)
    else circ(x, 10, 3, ESCURO) end
  end
  -- alvos
  for j = 1, MAX_ALVOS do
    local a = alvos[j]
    if a.ativo then
      if a.tipo == 1 then
        local cx, cy, r = a.x + 5, a.y + 5, 5 + (frame // 8) % 2
        ui.trisfill(cx, cy - r, cx - r, cy, cx + r, cy, VERDE); ui.trisfill(cx, cy + r, cx - r, cy, cx + r, cy, VERDE)
        ui.circfill(cx, cy, 1, BRANCO)
        if passo == "mover" then   -- trilha pontilhada da nave ate o pacote
          local sx, sy = p.x + 8, p.y + 8
          for k = 1, 5 do
            local f = (k + (frame // 6) % 2 * 0.5) / 6
            ui.rectfill(sx + (cx - sx) * f, sy + (cy - sy) * f, sx + (cx - sx) * f + 1, sy + (cy - sy) * f + 1, VERDE)
          end
        end
      elseif a.tipo == 2 then
        local gx = (math.random() < 0.1) and math.random(-2, 2) or 0
        ui.rectfill(a.x + gx, a.y, a.x + a.w + gx, a.y + a.h, VERM)
        ui.rectfill(a.x + 3, a.y + 3 + (frame // 5) % 6, a.x + a.w - 3, a.y + 5 + (frame // 5) % 6, ROXO)
      else
        ui.rectfill(a.x, a.y, a.x + a.w, a.y + a.h, CINZA)
        ui.rect(a.x - 2, a.y - 2, a.x + a.w + 2, a.y + a.h + 2, BRANCO)
        ui.rectfill(a.x + 10, a.y + 10, a.x + a.w - 10, a.y + a.h - 10, VERM)
      end
    end
  end
  -- emissor do virus nas paredes (carrega antes de disparar)
  if (passo == "escudo" or passo == "dash") and tut_pausa == 0 then
    ui.trisfill(W - 4, H / 2 - 14, W - 4, H / 2 + 14, W - 20, H / 2, T.cor2)
    if not tut_parede_on and tut_t > 30 then circ(W - 12, H / 2, (tut_t - 30) // 3, passo == "dash" and BRANCO or T.cor2) end
  end
  -- dash: na camera lenta, setas ">>" na frente da nave apontando para a parede
  if passo == "dash" and escala_tiros < 1 and (frame // 4) % 2 == 0 then
    for k = 0, 1 do
      local ax = p.x + p.w + 6 + k * 9
      ui.trisfill(ax, p.y + 2, ax, p.y + 14, ax + 7, p.y + 8, BRANCO)
    end
  end
  -- falha: borda roxa piscando enquanto os controles estao invertidos
  if passo == "debug" and fase == "ativo" and (frame // 6) % 2 == 0 then
    ui.rect(0, 0, W - 1, H - 1, ROXO); ui.rect(2, 2, W - 3, H - 3, ROXO)
  end
  -- acerto: anel verde crescendo
  if tut_pausa > 0 then circ(p.x + 8, p.y + 8, (50 - tut_pausa) * 2, VERDE) end
  desenha_controle(TUT_BOTAO[passo])
end

end -- tutorial

-- ================= HISTORIA (abertura antes do tutorial) =================
do
-- Tudo desenhado em codigo (Jupiter, buraco de minhoca, efeitos); naves = sprites existentes.
-- B avanca (completa o texto / proxima cena); pausa (START / L+R) pula. Toca na 1a partida; X no titulo repete.
local HIST = {
  { dur = 300, l1 = "ANO 2387. ORBITA DE JUPITER.",        l2 = "Um piloto solitario cruza o vazio." },
  { dur = 300, l1 = "Um buraco de minhoca se abre a frente.", l2 = "Velocidade da luz. Impossivel desviar." },
  { dur = 120, l1 = "",                                    l2 = "" },
  { dur = 300, l1 = "FALHA NO SISTEMA: materia duplicada.", l2 = "A nave... e o piloto. Agora sao dois." },
  { dur = 300, l1 = "Seu outro eu foi corrompido: " .. T.nome2, l2 = "E ele quer apagar o original." },
  { dur = 300, l1 = "Venca seu alter ego.",                l2 = "Restaure o sistema." },
}
local h_cena, h_t = 1, 0

historia_comeca = function() h_cena, h_t, estado = 1, 0, "historia" end

local function historia_fim()
  PROG.hist = true
  if not PROG.tut then tut_comeca() else nova_rodada() end
end

local function nave_hist(id, x, y, flip)
  local spr = NAVE_SPR[id]
  if spr then ui.spr(spr, x - NAVE_TAM / 2, y - NAVE_TAM / 2, flip)
  else forma("tri", x - 8, y - 8, 16, 16, id == 1 and T.cor1 or T.cor2, flip and -1 or 1) end
end

local function jupiter(cx, cy, r)
  ui.circfill(cx, cy, r, BEGE)
  for dy = -r + 4, r - 4, 7 do                -- faixas: linhas cortadas na corda do circulo
    local hw = math.floor(math.sqrt(r * r - dy * dy))
    local c = ((dy + r) // 7) % 3 == 0 and MARROM or (((dy + r) // 7) % 3 == 1 and LARANJA or BEGE)
    ui.line(cx - hw, cy + dy, cx + hw, cy + dy, c); ui.line(cx - hw, cy + dy + 1, cx + hw, cy + dy + 1, c)
  end
  ui.circfill(cx - r // 3, cy + r // 3, r // 6, VERM)   -- grande mancha vermelha
end

local function minhoca(cx, cy, tam)
  for k = 0, 5 do
    local r = (tam - k * 7 + (frame // 2) % 7)
    if r > 1 then circ(cx, cy, r, (k + frame // 4) % 3 == 0 and BRANCO or (k % 2 == 0 and ROXO or AZUL)) end
  end
  ui.circfill(cx, cy, math.max(1, tam // 5), PRETO)
end

atualiza_historia = function()
  local cena = HIST[h_cena]
  h_t = h_t + 1
  local n = math.floor(h_t * 1.5)
  local completo = n >= #cena.l1 + #cena.l2 + 8
  if apertou_pausa() then historia_fim(); return end
  if apertou(ACAO) then
    if completo or cena.l1 == "" then h_t = cena.dur
    else h_t = math.min(cena.dur - 1, math.ceil((#cena.l1 + #cena.l2 + 8) / 1.5)) end   -- so completa o texto
  end
  if h_t >= cena.dur and (completo or cena.l1 == "") then
    h_cena, h_t = h_cena + 1, 0
    if h_cena > #HIST then historia_fim(); return end
    cena = HIST[h_cena]
    if h_cena == 3 then shake = 40 end
  end

  ui.cls(PRETO)
  local t = h_t
  -- estrelas: na cena 2 viram riscos de velocidade da luz
  local vel = (h_cena == 2) and (1 + t / 20) or 0.6
  for i = 1, #estrelas do
    local e = estrelas[i]
    e.x = e.x - e.v * vel
    if e.x < 0 then e.x = W end
    if h_cena == 2 and t > 60 then ui.line(e.x, e.y, e.x + e.v * vel * 3, e.y, e.v == 3 and BRANCO or CINZA)
    else ui.rectfill(e.x, e.y, e.x + 1, e.y + 1, e.v == 3 and BRANCO or CINZA) end
  end
  if shake > 0 then ui.camera(math.random(-5, 5), math.random(-5, 5)); shake = shake - 1 end

  local cy = 110
  if h_cena == 1 then
    jupiter(360, 100, 75)
    nave_hist(1, -20 + t * 0.9, cy + math.sin(t * 0.05) * 4, false)
  elseif h_cena == 2 then
    jupiter(360 - t * 2, 100, 75)
    minhoca(W - 70, cy, math.min(60, t // 3 + 4))
    local x = 160 + (t > 180 and (t - 180) * (t - 180) * 0.02 or 0)
    nave_hist(1, math.min(x, W - 70), cy, false)
  elseif h_cena == 3 then
    if t < 12 then ui.rectfill(0, 0, W, H, BRANCO) end
    for i = 1, 6 do
      local gy = math.random(0, H)
      ui.rectfill(0, gy, W, gy + math.random(1, 4), math.random(0, 2) == 0 and ROXO or (math.random(0, 1) == 0 and VERDE or VERM))
    end
  elseif h_cena == 4 then
    local off = math.min(28, t * 0.3)
    nave_hist(1, MEIO - 40, cy - off, false)
    if (t // 3) % 4 ~= 0 then nave_hist(2, MEIO - 40 + math.random(-2, 2), cy + off, false) end
    if math.random() < 0.3 then
      local gy = cy + off + math.random(-12, 12)
      ui.rectfill(MEIO - 60, gy, MEIO - 10, gy + 1, VERM)
    end
  elseif h_cena == 5 then
    nave_hist(1, MEIO - 120, cy, false)
    local ex = MEIO + math.min(120, t * 1.2)
    nave_hist(2, ex, cy, true)
    circ(ex, cy, 16 + (frame // 4) % 3, VERM)
    if t > 120 then
      local tx = ex - (t - 120) * 5
      if tx > MEIO - 110 then ui.rectfill(tx, cy - 2, tx + 6, cy + 2, VERM)
      else circ(MEIO - 120, cy, 14, AMAR); if t < 200 then explode(MEIO - 106, cy, AMAR, 1) end end
    end
  elseif h_cena == 6 then
    nave_hist(1, 70, cy, false)
    nave_hist(2, W - 70, cy, true)
    for y = 40, 180, 12 do ui.line(MEIO, y, MEIO, y + 5, CINZA) end
    local cor = (frame // 8) % 2 == 0 and AMAR or VERM
    centro(T.titulo, 60 + ((math.random() < 0.1) and math.random(-2, 2) or 0), cor)
  end
  for i = 1, MAX_PART do
    local q = parts[i]
    if q.vida > 0 then
      q.x, q.y, q.vida = q.x + q.vx, q.y + q.vy, q.vida - 1
      ui.rectfill(q.x, q.y, q.x + 2, q.y + 2, q.cor)
    end
  end
  ui.camera(0, 0)

  -- caixa de texto com efeito de digitacao
  if cena.l1 ~= "" then
    ui.rectfill(16, 206, W - 16, 258, ESCURO); ui.rect(16, 206, W - 16, 258, VERDE)
    ui.print(n >= #cena.l1 and cena.l1 or string.sub(cena.l1, 1, n), 28, 218, BRANCO)
    local n2 = n - #cena.l1 - 8
    if n2 > 0 then ui.print(n2 >= #cena.l2 and cena.l2 or string.sub(cena.l2, 1, n2), 28, 234, VERDE) end
    if completo and (frame // 20) % 2 == 0 then ui.trisfill(W - 34, 246, W - 26, 246, W - 30, 251, VERDE) end
  end
  -- cenas ja vistas: pontinhos
  for i = 1, #HIST do
    if i <= h_cena then ui.circfill(W - 20 - (#HIST - i) * 8, 10, 2, i == h_cena and BRANCO or CINZA) end
  end
end

end -- historia

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
  ui.clip(0, 0, W, H)
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
      if (t // 8) % 2 == 0 then centro(DIFICULDADES.critico.desbloq, 206, VERM) end
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
historia_comeca()   -- ao ligar: historia -> tutorial -> partida, sem parar no titulo

function update()
  le_botoes()
  frame = frame + 1
  aplica_paleta()
  ui.clip(0, 0, W, H)
  ui.camera(0, 0)
  if estado == "gameover" then desenha_gameover(); return end
  if estado == "boot" then desenha_boot(); return end
  if estado == "vitoria" then desenha_vitoria(); return end
  if estado == "historia" then atualiza_historia(); return end
  desenha_fundo()

  if estado == "titulo" then
    centro(T.titulo, 34, AMAR)
    centro(TXT_VS, 48, T.cor2)
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
        centro(i == dif_idx and d.sel or d.nome, y, cor)
      end
    end
    centro(DIFICULDADES[ORDEM_DIF[dif_idx]].desc, 200, ROXO)
    centro("naves: Cozy Space Ships por Bramble & Byte (CC-BY 4.0)", 248, CINZA)
    centro("asteroides: Space Shooter Redux por Kenney (CC0)", 258, CINZA)
    if (frame // 30) % 2 == 0 then centro(AJUDA[9], 222, VERDE) end
    centro(AJUDA[10], 234, CINZA)
    if apertou(ACAO) then
      reset()
      if not PROG.hist then historia_comeca() elseif not PROG.tut then tut_comeca() end
    elseif apertou(B_ESCUDO) then
      reset(); tut_comeca()
    elseif apertou(B_DEBUG) then
      reset(); historia_comeca()
    end
    return
  end

  local pulou = false   -- o mesmo L+R que pula o tutorial nao pode pausar a partida no mesmo frame
  if estado == "tutorial" then
    if apertou_pausa() then tut_fim(); pulou = true else atualiza_tutorial() end
  end

  if not pulou and (estado == "jogo" or estado == "contagem") and apertou_pausa() then
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
  if estado ~= "pausa" then atualiza_asteroides() end
  if estado ~= "pausa" then atualiza_tiros() end

  cam_dx, cam_dy = 0, 0
  if shake > 0 then
    cam_dx, cam_dy = math.random(-4, 4), math.random(-4, 4)
    ui.camera(cam_dx, cam_dy)
    shake = shake - 1
  end

  -- rastro do dash: ecos da nave encolhendo e esfriando de cor (branco -> cor da nave -> cinza)
  for _, p in ipairs(players) do
    if not (p.cpu and estado == "tutorial") then
      for k = 1, RASTRO_N do
        local tt = p.rastro_t[k]
        if tt and tt > 0 then
          local tam = 4 + tt // 2
          local c = tt > RASTRO_VIDA - 6 and BRANCO or (tt > 8 and p.cor or CINZA)
          local gx, gy = p.rastro_x[k] + 8, p.rastro_y[k] + 8
          if p.dir == 1 then ui.trisfill(gx - tam, gy - tam, gx - tam, gy + tam, gx + tam, gy, c)
          else ui.trisfill(gx + tam, gy - tam, gx + tam, gy + tam, gx - tam, gy, c) end
        end
      end
    end
  end
  for _, p in ipairs(players) do
    if p.vidas > 0 and not (p.cpu and estado == "tutorial") and (p.hit == 0 or (frame // 3) % 2 == 0) then
      local spr = T.forma == "nave" and NAVE_SPR[p.id]
      if spr then
        if (frame // 4) % 2 == 0 then   -- chama do motor atras do sprite
          local mx = p.dir == 1 and p.x - 8 or p.x + p.w + 4
          ui.rectfill(mx, p.y + 6, mx + 4, p.y + 10, LARANJA)
        end
        -- no console o Sprites nao tem width/height (so no SDK): usa o tamanho conhecido do PNG
        local sw, sh = tonumber(spr.width) or NAVE_TAM, tonumber(spr.height) or NAVE_TAM
        ui.spr(spr, p.x + p.w / 2 - sw / 2, p.y + p.h / 2 - sh / 2, p.dir == -1)
      else
        forma(T.forma, p.x, p.y, p.w, p.h, p.cor, p.dir)
      end
    end
    if p.vidas > 0 and not (p.cpu and estado == "tutorial") then
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
      local pl = PLASMA[t.dono]
      if t.laser and t.h > t.w and LASER_V then          -- parede de laser vertical (tutorial)
        ui.spr(LASER_V, t.x + 1, t.y)
      elseif t.laser then
        ui.rectfill(t.x, t.y, t.x + t.w, t.y + t.h, c); ui.rectfill(t.x, t.y + 2, t.x + t.w, t.y + t.h - 2, BRANCO)
      elseif pl and T.forma == "nave" then               -- plasma animado: janela de 10x10 sobre a tira de 4 quadros
        local qx, qy = math.floor(t.x + t.w / 2 - PLASMA_Q / 2), math.floor(t.y + t.h / 2 - PLASMA_Q / 2)
        ui.clip(qx - cam_dx, qy - cam_dy, PLASMA_Q, PLASMA_Q)
        ui.spr(pl, qx - ((frame // 8 + i) % 4) * PLASMA_Q, qy)
        ui.clip(0, 0, W, H)
      elseif T.forma == "nave" then                      -- plasma em codigo: bola pulsando com miolo branco
        local cx, cy = t.x + 2, t.y + 2
        ui.circfill(cx, cy, 3 + (frame // 4 + i) % 2, c)
        ui.circfill(cx, cy, 1, BRANCO)
      else forma(T.tiro_forma, t.x, t.y, 5, 5, c, t.dir) end
    end
  end
  for i = 1, MAX_AST do
    local a = asts[i]
    if a.ativo then
      local ti, spr = AST_TIPOS[a.tipo], AST_SPR[a.tipo]
      if spr then ui.spr(spr, a.x - ti.tam / 2, a.y - ti.tam / 2)
      else ui.circfill(a.x, a.y, ti.raio, CINZA) end
    end
  end
  for i = 1, MAX_PART do
    local p = parts[i]
    if p.vida > 0 then ui.rectfill(p.x, p.y, p.x + 2, p.y + 2, p.cor) end
  end

  ui.camera(0, 0)
  if estado == "tutorial" then desenha_tutorial(); return end
  desenha_hud()
  if estado == "jogo" then desenha_evento() end
  if msg_t > 0 then centro(msg_txt, 60, AMAR) end
  if estado == "pausa" then
    ui.rectfill(MEIO - 110, 100, MEIO + 110, 182, ESCURO); ui.rect(MEIO - 110, 100, MEIO + 110, 182, BRANCO)
    centro("PAUSA", 110, AMAR)
    centro(AJUDA[7], 128, BRANCO)
    centro(AJUDA[8], 142, CINZA)
    -- medidor de desempenho (so na pausa): FPS e memoria do console (ui.stat) ou do Lua
    local fps = ui.stat and ui.stat(7)
    local mem = ui.stat and ui.stat(0) or collectgarbage("count") * 1024
    ui.print(string.format("FPS %s  MEM %dKB  LUA %dKB", fps and tostring(math.floor(fps)) or "-",
      math.floor(mem / 1024), math.floor(collectgarbage("count"))), MEIO - 100, 170, CINZA)
  end
  centro(TXT_PLACAR[placar[1] * 3 + placar[2]] or "", 6, BRANCO)
  if estado == "contagem" then
    centro(TXT_RODADA[rodada] or "", 105, AMAR)
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
    centro(TXT_FINAL[placar[1] * 3 + placar[2]] or "", 130, AMAR)
  end
end
