--!nocheck
--!nolint
--[[
╔══════════════════════════════════════════════════════════════════╗
║  AuroraUI  v1.3.0  —  Biblioteca de UI para Roblox (Luau)        ║
║  PC + Mobile • 8 temas • Minimizar/Normal • Zero dependências    ║
╚══════════════════════════════════════════════════════════════════╝

Uso rápido:
    local Aurora = require(caminho.AuroraUI)         -- ModuleScript
    -- ou: local Aurora = loadstring(game:HttpGet("URL_DO_ARQUIVO"))()
    local UI  = Aurora.new({ Title = "Meu Painel", Theme = "Midnight" })
    local tab = UI:CreateTab("Principal")
    tab:CreateButton({ Name = "Executar", Callback = function() print("ok") end })

Visual "vidro" (v1.3) — janela translúcida com imagem de fundo opcional:
    Aurora.new({ Title = "Foxname", Subtitle = "discord.gg/xyz", Icon = "sparkles",
                 Background = 1234567890,  -- ID de imagem (ou caminho de arquivo em executores)
                 BackgroundOpacity = 1,    -- opacidade da imagem (0-1)
                 Dim = 0.4,                -- escurecimento sobre a imagem (0-1)
                 Glass = 1,                -- 0 = sólido, 1 = vidro total
                 AccentLine = false })     -- linha de gradiente no header
    UI:SetBackground(id) • UI:SetGlass(0-1) • UI:SetBackgroundDim(0-1)
    UI:SetSubtitle("texto") • UI:Maximize()

Organização do arquivo (seções):
    1. Serviços e utilidades (Signal, Maid, Tween, Dragger)
    2. Temas
    3. Window (janela, abas, minimizar, FAB, notificações, modal, palette)
    4. Tab (todos os componentes)
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UIS              = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local SoundService     = game:GetService("SoundService")
local Lighting         = game:GetService("Lighting")
local RunService      = game:GetService("RunService")
local TextService     = game:GetService("TextService")
local HttpService     = game:GetService("HttpService") -- só JSON, sem requisições

local Aurora = { Version = "1.3.0" }

----------------------------------------------------------------------
-- 1. UTILIDADES
----------------------------------------------------------------------

-- Signal: evento leve (substitui BindableEvent)
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ _h = {} }, Signal) end
function Signal:Connect(fn)
	local c = { fn = fn }
	table.insert(self._h, c)
	return { Disconnect = function()
		local i = table.find(self._h, c)
		if i then table.remove(self._h, i) end
	end }
end
function Signal:Fire(...)
	for _, c in ipairs(table.clone(self._h)) do task.spawn(c.fn, ...) end
end

-- Maid: limpeza automática de conexões/instâncias
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _t = {} }, Maid) end
function Maid:Add(x) table.insert(self._t, x) return x end
function Maid:Clean()
	for _, x in ipairs(self._t) do
		local t = typeof(x)
		if t == "RBXScriptConnection" then x:Disconnect()
		elseif t == "Instance" then x:Destroy()
		elseif type(x) == "table" and x.Disconnect then x:Disconnect()
		elseif type(x) == "function" then pcall(x) end
	end
	table.clear(self._t)
end

local EASE = Enum.EasingStyle
local DIR = Enum.EasingDirection

local function tw(o, props, t, style, dir)
	local tween = TweenService:Create(o, TweenInfo.new(t or 0.2, style or EASE.Quint, dir or DIR.Out), props)
	tween:Play()
	return tween
end

local function new(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if props and props.Parent then o.Parent = props.Parent end
	return o
end

local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = p }) end
local function padding(p, l, t, r, b)
	return new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t),
		PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b), Parent = p })
end
local function call(fn, ...)
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok then warn("[AuroraUI] erro em callback: " .. tostring(err)) end
	end
end
local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

-- Drag de valor (sliders, color picker): fn(ratioX, ratioY) em [0,1]
local function bindDrag(maid, frame, fn)
	local dragging = false
	local function upd(pos)
		local a, s = frame.AbsolutePosition, frame.AbsoluteSize
		fn(math.clamp((pos.X - a.X) / math.max(s.X, 1), 0, 1), math.clamp((pos.Y - a.Y) / math.max(s.Y, 1), 0, 1))
	end
	frame.InputBegan:Connect(function(i)
		if isPress(i) then dragging = true upd(i.Position) end
	end)
	maid:Add(UIS.InputChanged:Connect(function(i)
		if dragging and isMove(i) then upd(i.Position) end
	end))
	maid:Add(UIS.InputEnded:Connect(function(i)
		if isPress(i) then dragging = false end
	end))
end

-- Arrastar janela (mouse + touch). onTap: toque curto. onEnd(delta, posInicial, ehTouch, movido)
local function makeDraggable(maid, handle, target, onTap, onEnd)
	local dragging, startIn, startPos, moved, touch = false, nil, nil, 0, false
	handle.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging, moved, touch = true, 0, i.UserInputType == Enum.UserInputType.Touch
			startIn, startPos = i.Position, target.Position
		end
	end)
	maid:Add(UIS.InputChanged:Connect(function(i)
		if dragging and isMove(i) then
			local d = i.Position - startIn
			moved = math.max(moved, d.Magnitude)
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	maid:Add(UIS.InputEnded:Connect(function(i)
		if dragging and isPress(i) then
			dragging = false
			local d = i.Position - startIn
			if moved < 6 and onTap then onTap() end
			if onEnd then onEnd(d, startPos, touch, moved) end
		end
	end))
end

----------------------------------------------------------------------
-- 2. TEMAS
----------------------------------------------------------------------
local function mk(bg, surface, element, accent, accent2, text, sub, stroke)
	local a = Color3.fromHex(accent)
	local lum = 0.299 * a.R + 0.587 * a.G + 0.114 * a.B
	local el = Color3.fromHex(element)
	local light = (0.299 * el.R + 0.587 * el.G + 0.114 * el.B) > 0.6
	return {
		Background = Color3.fromHex(bg), Surface = Color3.fromHex(surface), Element = el,
		ElementHover = el:Lerp(light and Color3.new(0, 0, 0) or Color3.new(1, 1, 1), 0.07),
		Accent = a, Accent2 = Color3.fromHex(accent2),
		OnAccent = lum > 0.6 and Color3.fromHex("#101010") or Color3.new(1, 1, 1),
		Text = Color3.fromHex(text), SubText = Color3.fromHex(sub), Stroke = Color3.fromHex(stroke),
		Success = Color3.fromHex(light and "#18A66B" or "#3DDC97"),
		Warning = Color3.fromHex(light and "#D98A00" or "#FFB020"),
		Error = Color3.fromHex(light and "#D93A50" or "#FF5C70"),
	}
end
--                 bg         surface    element    accent     accent2    text       sub        stroke
local Themes = {
	Glass     = mk("#0A0E1A", "#0F1526", "#18203A", "#4C8DFF", "#7FB0FF", "#F4F7FF", "#9AA6C4", "#2B3757"),
	Dark      = mk("#0F1117", "#151821", "#1D212C", "#6C63FF", "#A78BFA", "#F2F4F8", "#9AA3B2", "#2A2F3C"),
	Light     = mk("#F4F6FA", "#FFFFFF", "#EEF1F7", "#5B5BF0", "#8B7CF6", "#1A1D26", "#5B6475", "#D8DDE8"),
	Midnight  = mk("#080B1A", "#0E1328", "#161C38", "#4D7CFF", "#7AA2FF", "#EAF0FF", "#8F9BC4", "#243056"),
	Ocean     = mk("#07181F", "#0B2530", "#10333F", "#14B8D4", "#5EEAD4", "#E6FAFF", "#86B7C4", "#1B4A59"),
	Sunset    = mk("#1A0F14", "#26141B", "#331B24", "#FF7A45", "#FF4D8D", "#FFF1EA", "#C79A8C", "#4A2A33"),
	Neon      = mk("#08080C", "#0F0F16", "#16161F", "#00FFA3", "#00C2FF", "#F0FFF8", "#8AA89B", "#1E3A30"),
	Cyberpunk = mk("#0D0221", "#1A0637", "#260B4D", "#FF2A6D", "#05D9E8", "#FFF9D6", "#B79BD9", "#4A1F85"),
	Pastel    = mk("#FDF6FB", "#FFFFFF", "#F6ECF6", "#B388EB", "#F7A8C8", "#3B2F4A", "#7C6A8F", "#E6D3EF"),
}
local ThemeOrder = { "Glass", "Dark", "Light", "Midnight", "Ocean", "Sunset", "Neon", "Cyberpunk", "Pastel" }
Aurora.Themes, Aurora.ThemeOrder = Themes, ThemeOrder

local SOUNDS = { click = "rbxassetid://6895079853", open = "rbxassetid://6895079853", close = "rbxassetid://6895079853" }

----------------------------------------------------------------------
-- 2b. ÍCONES VETORIAIS (sem assets: desenhados com Frames, seguem o tema)
----------------------------------------------------------------------
--[[ Cada ícone é uma lista de primitivas numa grade 24x24 (estilo Lucide, traço 2):
       {"l",x1,y1,x2,y2}  linha com ponta redonda     {"c",cx,cy,r}  círculo (contorno)
       {"d",cx,cy,r}      ponto preenchido            {"r",x,y,w,h,raio}  retângulo (contorno)
       {"f",x,y,w,h,raio} retângulo preenchido
     Escalam sem perder nitidez e recolorem com o tema. Para criar o seu:
       Aurora.RegisterIcon("meu", { {"l",4,12,20,12}, {"c",12,12,6} })
     Também aceita imagem: Aurora.RegisterIcon("logo", { Image = "rbxassetid://...", Offset = Vector2.new(), Size = Vector2.new() }) ]]
local Icons, IconAliases = {}, {
	settings = "gear", close = "x", success = "check-circle", error = "x-circle", warning = "alert",
	cog = "gear", search = "search", menu = "menu", cursor = "pointer", dashboard = "grid", pencil = "edit",
}
Aurora.Icons = Icons

local function L(x1, y1, x2, y2) return { { "l", x1, y1, x2, y2 } } end
local function C(x, y, r) return { { "c", x, y, r } } end
local function D(x, y, r) return { { "d", x, y, r or 1.3 } } end
local function R(x, y, w, h, r) return { { "r", x, y, w, h, r or 2 } } end
local function F(x, y, w, h, r) return { { "f", x, y, w, h, r or 1 } } end
local function PL(pts, closed)
	local out = {}
	for i = 1, #pts - 1 do out[#out + 1] = { "l", pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2] } end
	if closed then out[#out + 1] = { "l", pts[#pts][1], pts[#pts][2], pts[1][1], pts[1][2] } end
	return out
end
local function arc(cx, cy, r, a0, a1) -- graus, anti-horário, y para cima
	local pts, n = {}, math.max(4, math.ceil(math.abs(a1 - a0) / 18))
	for i = 0, n do
		local a = math.rad(a0 + (a1 - a0) * i / n)
		pts[#pts + 1] = { cx + r * math.cos(a), cy - r * math.sin(a) }
	end
	return pts
end
local function cat(...)
	local out = {}
	for _, t in ipairs({ ... }) do for _, p in ipairs(t) do out[#out + 1] = p end end
	return out
end
local function rays(cx, cy, r0, r1, n, off)
	local out = {}
	for i = 0, n - 1 do
		local a = math.rad((off or 0) + 360 * i / n)
		out[#out + 1] = { "l", cx + r0 * math.cos(a), cy - r0 * math.sin(a), cx + r1 * math.cos(a), cy - r1 * math.sin(a) }
	end
	return out
end

local I = Icons
I["home"] = cat(PL({ { 3, 11 }, { 12, 3 }, { 21, 11 } }), L(5, 10, 5, 21), L(19, 10, 19, 21), L(5, 21, 19, 21), PL({ { 10, 21 }, { 10, 15 }, { 14, 15 }, { 14, 21 } }))
I["gear"] = cat(C(12, 12, 3), C(12, 12, 7), rays(12, 12, 8.6, 10.8, 8, 0))
I["sliders"] = cat(L(4, 6, 8, 6), L(12, 6, 20, 6), C(10, 6, 2), L(4, 12, 12, 12), L(16, 12, 20, 12), C(14, 12, 2), L(4, 18, 6, 18), L(10, 18, 20, 18), C(8, 18, 2))
I["user"] = cat(C(12, 8, 4), PL(arc(12, 22, 8, 12, 168)))
I["users"] = cat(C(9, 8, 3.5), PL(arc(9, 21, 6.5, 14, 166)), C(17, 9, 2.8), PL(arc(17.5, 20, 5, 25, 90)))
I["search"] = cat(C(10.5, 10.5, 6.5), L(15.5, 15.5, 21, 21))
I["bell"] = cat(PL(arc(12, 10, 6, 0, 180)), L(6, 10, 5, 17), L(18, 10, 19, 17), L(4, 17, 20, 17), L(10.5, 20.5, 13.5, 20.5), L(12, 3, 12, 4.2))
I["check"] = cat(L(4, 12.5, 9.5, 18), L(9.5, 18, 20, 6.5))
I["x"] = cat(L(5, 5, 19, 19), L(19, 5, 5, 19))
I["plus"] = cat(L(12, 5, 12, 19), L(5, 12, 19, 12))
I["minus"] = L(5, 12, 19, 12)
I["menu"] = cat(L(4, 6, 20, 6), L(4, 12, 20, 12), L(4, 18, 20, 18))
I["chevron-down"] = PL({ { 6, 9 }, { 12, 15 }, { 18, 9 } })
I["chevron-up"] = PL({ { 6, 15 }, { 12, 9 }, { 18, 15 } })
I["chevron-left"] = PL({ { 15, 6 }, { 9, 12 }, { 15, 18 } })
I["chevron-right"] = PL({ { 9, 6 }, { 15, 12 }, { 9, 18 } })
I["arrow-right"] = cat(L(4, 12, 20, 12), PL({ { 14, 6 }, { 20, 12 }, { 14, 18 } }))
I["arrow-left"] = cat(L(20, 12, 4, 12), PL({ { 10, 6 }, { 4, 12 }, { 10, 18 } }))
I["info"] = cat(C(12, 12, 9), D(12, 7.8, 1.2), L(12, 11, 12, 16.5))
I["alert"] = cat(PL({ { 12, 3.5 }, { 21.5, 19.5 }, { 2.5, 19.5 } }, true), L(12, 9.5, 12, 14), D(12, 16.8, 1.1))
I["x-circle"] = cat(C(12, 12, 9), L(9, 9, 15, 15), L(15, 9, 9, 15))
I["check-circle"] = cat(C(12, 12, 9), PL({ { 8, 12.5 }, { 11, 15.5 }, { 16, 9 } }))
I["lock"] = cat(R(5, 11, 14, 10, 2.5), PL({ { 8, 11 }, { 8, 8 }, { 10, 5.5 }, { 14, 5.5 }, { 16, 8 }, { 16, 11 } }), D(12, 16, 1.2))
I["unlock"] = cat(R(5, 11, 14, 10, 2.5), PL({ { 8, 11 }, { 8, 8 }, { 10, 5.5 }, { 14, 5.5 }, { 16, 8 } }), D(12, 16, 1.2))
I["key"] = cat(C(8, 15, 4), L(11, 12, 20, 3), L(17, 6, 20, 9), L(15, 8, 17, 10))
I["eye"] = cat(PL({ { 2, 12 }, { 6, 7.5 }, { 12, 5.5 }, { 18, 7.5 }, { 22, 12 }, { 18, 16.5 }, { 12, 18.5 }, { 6, 16.5 } }, true), C(12, 12, 3))
I["eye-off"] = cat(PL({ { 2, 12 }, { 6, 7.5 }, { 12, 5.5 }, { 18, 7.5 }, { 22, 12 }, { 18, 16.5 }, { 12, 18.5 }, { 6, 16.5 } }, true), C(12, 12, 3), L(4, 4, 20, 20))
I["heart"] = PL({ { 12, 20 }, { 4.5, 12.5 }, { 3.5, 8.5 }, { 6, 5.5 }, { 9.5, 5.5 }, { 12, 8.5 }, { 14.5, 5.5 }, { 18, 5.5 }, { 20.5, 8.5 }, { 19.5, 12.5 } }, true)
I["star"] = PL({ { 12, 2.8 }, { 14.8, 9 }, { 21.5, 9.6 }, { 16.4, 14 }, { 18, 20.8 }, { 12, 17.3 }, { 6, 20.8 }, { 7.6, 14 }, { 2.5, 9.6 }, { 9.2, 9 } }, true)
I["zap"] = PL({ { 13, 2 }, { 4, 14 }, { 12, 14 }, { 11, 22 }, { 20, 10 }, { 12, 10 } }, true)
I["shield"] = cat(PL({ { 12, 2.5 }, { 20, 5.5 }, { 20, 12 }, { 17, 18 }, { 12, 21.5 }, { 7, 18 }, { 4, 12 }, { 4, 5.5 } }, true), PL({ { 8.5, 12 }, { 11, 14.5 }, { 15.5, 9.5 } }))
I["target"] = cat(C(12, 12, 9), C(12, 12, 4.5), D(12, 12, 1.2))
I["crosshair"] = cat(C(12, 12, 6.5), L(12, 2, 12, 7), L(12, 17, 12, 22), L(2, 12, 7, 12), L(17, 12, 22, 12), D(12, 12, 1))
I["sword"] = cat(L(4.5, 19.5, 19.5, 4.5), L(19.5, 4.5, 20, 9.5), L(19.5, 4.5, 14.5, 4), L(6, 12, 12, 18), L(4, 20, 2.5, 21.5))
I["folder"] = PL({ { 3, 6 }, { 9, 6 }, { 11, 9 }, { 21, 9 }, { 21, 19 }, { 3, 19 } }, true)
I["file"] = cat(PL({ { 6, 3 }, { 14, 3 }, { 19, 8 }, { 19, 21 }, { 6, 21 } }, true), L(14, 3, 14, 8), L(14, 8, 19, 8))
I["code"] = cat(PL({ { 8, 7 }, { 3, 12 }, { 8, 17 } }), PL({ { 16, 7 }, { 21, 12 }, { 16, 17 } }), L(14, 5, 10, 19))
I["terminal"] = cat(R(3, 4, 18, 16, 2.5), PL({ { 7, 9 }, { 10, 12 }, { 7, 15 } }), L(12, 15, 17, 15))
I["globe"] = cat(C(12, 12, 9), L(3, 12, 21, 12), R(8, 3, 8, 18, 4))
I["play"] = PL({ { 7, 4 }, { 19, 12 }, { 7, 20 } }, true)
I["pause"] = cat(F(6.5, 5, 3.5, 14, 1.2), F(14, 5, 3.5, 14, 1.2))
I["refresh"] = cat(PL(arc(12, 12, 8, 55, -235)), L(7.4, 5.45, 3, 5.2), L(7.4, 5.45, 6.2, 9.8))
I["loader"] = PL(arc(12, 12, 8, 100, -160))
I["download"] = cat(L(12, 3, 12, 15), PL({ { 7, 10 }, { 12, 15 }, { 17, 10 } }), PL({ { 4, 17 }, { 4, 21 }, { 20, 21 }, { 20, 17 } }))
I["upload"] = cat(L(12, 15, 12, 3), PL({ { 7, 8 }, { 12, 3 }, { 17, 8 } }), PL({ { 4, 17 }, { 4, 21 }, { 20, 21 }, { 20, 17 } }))
I["trash"] = cat(L(4, 7, 20, 7), PL({ { 9, 7 }, { 9, 4 }, { 15, 4 }, { 15, 7 } }), PL({ { 6, 7 }, { 7, 21 }, { 17, 21 }, { 18, 7 } }), L(10, 11, 10, 17), L(14, 11, 14, 17))
I["copy"] = cat(R(9, 9, 12, 12, 2.5), PL({ { 15, 9 }, { 15, 6 }, { 5, 6 }, { 5, 16 }, { 9, 16 } }))
I["save"] = cat(R(4, 4, 16, 16, 2.5), PL({ { 8, 4 }, { 8, 9 }, { 16, 9 } }), PL({ { 8, 20 }, { 8, 14 }, { 16, 14 }, { 16, 20 } }))
I["edit"] = cat(PL({ { 4, 20 }, { 5, 15 }, { 16, 4 }, { 20, 8 }, { 9, 19 } }, true), L(13.5, 6.5, 17.5, 10.5))
I["pin"] = cat(PL({ { 12, 22 }, { 5.5, 14 }, { 5, 9 }, { 8, 4.5 }, { 12, 3 }, { 16, 4.5 }, { 19, 9 }, { 18.5, 14 } }, true), C(12, 9.5, 2.5))
I["wifi"] = cat(PL(arc(12, 19, 5, 45, 135)), PL(arc(12, 19, 9.5, 45, 135)), PL(arc(12, 19, 14, 45, 135)), D(12, 19.5, 1.2))
I["volume"] = cat(PL({ { 3, 9 }, { 7, 9 }, { 12, 4.5 }, { 12, 19.5 }, { 7, 15 }, { 3, 15 } }, true), PL(arc(12, 12, 5, -40, 40)), PL(arc(12, 12, 9, -45, 45)))
I["music"] = cat(C(7, 18, 3), C(17, 16, 3), L(10, 18, 10, 6), L(20, 16, 20, 4), L(10, 6, 20, 4))
I["pointer"] = PL({ { 5, 3 }, { 5, 19 }, { 9.5, 15 }, { 13, 21 }, { 15.5, 19.8 }, { 12, 14 }, { 18, 14 } }, true)
I["layers"] = cat(PL({ { 12, 3 }, { 22, 8.5 }, { 12, 14 }, { 2, 8.5 } }, true), PL({ { 2, 13 }, { 12, 18.5 }, { 22, 13 } }))
I["grid"] = cat(R(3, 3, 7.5, 7.5, 2), R(13.5, 3, 7.5, 7.5, 2), R(3, 13.5, 7.5, 7.5, 2), R(13.5, 13.5, 7.5, 7.5, 2))
I["power"] = cat(PL(arc(12, 13, 8, 125, 415)), L(12, 3, 12, 12))
I["crown"] = PL({ { 3, 18 }, { 3, 7 }, { 8, 12 }, { 12, 5 }, { 16, 12 }, { 21, 7 }, { 21, 18 } }, true)
I["cpu"] = cat(R(6, 6, 12, 12, 2.5), R(9.5, 9.5, 5, 5, 1), L(9, 2.5, 9, 6), L(15, 2.5, 15, 6), L(9, 18, 9, 21.5), L(15, 18, 15, 21.5), L(2.5, 9, 6, 9), L(2.5, 15, 6, 15), L(18, 9, 21.5, 9), L(18, 15, 21.5, 15))
I["database"] = cat(R(4, 3, 16, 6, 3), R(4, 9, 16, 6, 3), R(4, 15, 16, 6, 3))
I["activity"] = PL({ { 2, 12 }, { 6, 12 }, { 9, 4 }, { 15, 20 }, { 18, 12 }, { 22, 12 } })
I["bar-chart"] = cat(F(4, 12, 4, 8, 1.2), F(10, 6, 4, 14, 1.2), F(16, 3, 4, 17, 1.2))
I["gamepad"] = cat(R(2, 7, 20, 11, 5.5), L(7, 10.5, 7, 14.5), L(5, 12.5, 9, 12.5), D(16, 11.2, 1.1), D(18.5, 13.8, 1.1))
I["sparkles"] = cat(PL({ { 12, 3 }, { 14.2, 9.8 }, { 21, 12 }, { 14.2, 14.2 }, { 12, 21 }, { 9.8, 14.2 }, { 3, 12 }, { 9.8, 9.8 } }, true))
I["bookmark"] = PL({ { 6, 3 }, { 18, 3 }, { 18, 21 }, { 12, 16 }, { 6, 21 } }, true)
I["filter"] = PL({ { 3, 4 }, { 21, 4 }, { 14, 12.5 }, { 14, 20 }, { 10, 18 }, { 10, 12.5 } }, true)
I["moon"] = PL(cat(arc(12, 12, 9, 0, -270), arc(16.5, 7.5, 6.364, 135, 315)))
I["sun"] = cat(C(12, 12, 4), rays(12, 12, 7, 9.8, 8, 0))
I["flag"] = cat(L(5, 3, 5, 21), PL({ { 5, 4 }, { 19, 4 }, { 16, 8.5 }, { 19, 13 }, { 5, 13 } }))
I["clock"] = cat(C(12, 12, 9), L(12, 7, 12, 12), L(12, 12, 15.5, 14))
I["list"] = cat(L(9, 6, 20, 6), L(9, 12, 20, 12), L(9, 18, 20, 18), D(4.5, 6, 1.2), D(4.5, 12, 1.2), D(4.5, 18, 1.2))
I["mail"] = cat(R(3, 5, 18, 14, 2.5), PL({ { 3, 7.5 }, { 12, 13.5 }, { 21, 7.5 } }))
I["message"] = cat(R(3, 4, 18, 13, 3), PL({ { 8, 17 }, { 8, 21 }, { 12.5, 17 } }))
I["expand"] = cat(PL({ { 4, 9 }, { 4, 4 }, { 9, 4 } }), PL({ { 15, 4 }, { 20, 4 }, { 20, 9 } }), PL({ { 20, 15 }, { 20, 20 }, { 15, 20 } }), PL({ { 9, 20 }, { 4, 20 }, { 4, 15 } }))
I["rocket"] = cat(PL({ { 12, 2.5 }, { 16.5, 8 }, { 16.5, 15 }, { 7.5, 15 }, { 7.5, 8 } }, true), C(12, 9.5, 1.8), PL({ { 7.5, 12 }, { 4.5, 16 }, { 7.5, 15 } }), PL({ { 16.5, 12 }, { 19.5, 16 }, { 16.5, 15 } }), L(12, 17, 12, 21.5))

function Aurora.RegisterIcon(name, spec) Icons[name] = spec end
function Aurora.IconNames()
	local t = {}
	for n in pairs(Icons) do table.insert(t, n) end
	table.sort(t)
	return t
end

-- Constrói o ícone dentro de `parent`. Retorna { Frame, SetColor(cor, tempo) }
local function buildIcon(parent, name, size, color)
	local prims = Icons[name]
	local k, sw = 24, 2
	local px = math.max(1, size * sw / k)
	local holder = new("Frame", { Name = "Icon_" .. name, BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), Parent = parent })
	local fills, strokes = {}, {}
	local function S(v) return v / k end
	for _, p in ipairs(prims) do
		local t = p[1]
		if t == "l" then
			local dx, dy = p[4] - p[2], p[5] - p[3]
			local len = math.sqrt(dx * dx + dy * dy)
			local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = color,
				Position = UDim2.fromScale(S((p[2] + p[4]) / 2), S((p[3] + p[5]) / 2)), Size = UDim2.fromScale(S(len + sw), S(sw)),
				Rotation = math.deg(math.atan2(dy, dx)), Parent = holder })
			new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
			table.insert(fills, f)
		elseif t == "d" then
			local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = color,
				Position = UDim2.fromScale(S(p[2]), S(p[3])), Size = UDim2.fromScale(S(p[4] * 2), S(p[4] * 2)), Parent = holder })
			new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
			table.insert(fills, f)
		elseif t == "c" then
			local d = p[4] * 2 - sw
			local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0,
				Position = UDim2.fromScale(S(p[2]), S(p[3])), Size = UDim2.fromScale(S(d), S(d)), Parent = holder })
			new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
			table.insert(strokes, new("UIStroke", { Thickness = px, Color = color, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f }))
		elseif t == "r" then
			local w, h = p[4] - sw, p[5] - sw
			local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0,
				Position = UDim2.fromScale(S(p[2] + p[4] / 2), S(p[3] + p[5] / 2)), Size = UDim2.fromScale(S(w), S(h)), Parent = holder })
			new("UICorner", { CornerRadius = UDim.new(math.min(0.5, (p[6] or 2) / math.min(w, h)), 0), Parent = f })
			table.insert(strokes, new("UIStroke", { Thickness = px, Color = color, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f }))
		elseif t == "f" then
			local f = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = color, Position = UDim2.fromScale(S(p[2]), S(p[3])),
				Size = UDim2.fromScale(S(p[4]), S(p[5])), Parent = holder })
			new("UICorner", { CornerRadius = UDim.new(math.min(0.5, (p[6] or 1) / math.min(p[4], p[5])), 0), Parent = f })
			table.insert(fills, f)
		end
	end
	local obj: any = { Frame = holder }
	function obj:SetColor(c, t)
		for _, f in ipairs(fills) do
			if t and t > 0 then tw(f, { BackgroundColor3 = c }, t) else f.BackgroundColor3 = c end
		end
		for _, st in ipairs(strokes) do
			if t and t > 0 then tw(st, { Color = c }, t) else st.Color = c end
		end
	end
	return obj
end

----------------------------------------------------------------------
-- 3. WINDOW
----------------------------------------------------------------------
-- transparência base (com Glass = 1) de cada cor de fundo
local GLASS = { Surface = 0.4, Element = 0.5, Background = 0.55 }

local Window, Tab = {}, {}
Window.__index, Tab.__index = Window, Tab

function Aurora.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Window)
	self.Maid = Maid.new()
	self.Flags, self.Setters, self.Actions, self.Tabs, self.Consoles = {}, {}, {}, {}, {}
	self._themed, self._refreshers = {}, {}
	self.FlagChanged = Signal.new()
	self.Destroyed = Signal.new()
	self.Glass = math.clamp(opts.Glass or 1, 0, 1)
	self.ThemeName = Themes[opts.Theme] and opts.Theme or "Glass"
	self.Theme = Themes[self.ThemeName]
	self.Touch = UIS.TouchEnabled and not UIS.MouseEnabled
	self.RowH = self.Touch and 44 or 36
	self.Sounds = opts.Sounds == true
	self.ToggleKey = opts.ToggleKey or Enum.KeyCode.RightShift
	self.UserScale, self.UserCompact, self.Minimized, self.Visible = 1, false, false, true
	self.History, self.Unread, self.DND = {}, 0, false
	self.MaxNotifs = opts.MaxNotifications or 5
	self._nActive, self._nQueue, self._nById, self._nSeq, self._nWidth = 0, {}, {}, 0, 300

	-- ScreenGui (CoreGui para executores, PlayerGui para jogos normais)
	local gui = new("ScreenGui", { Name = opts.Name or ("AuroraUI_" .. math.random(1000, 9999)),
		ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999 })
	local parent
	if opts.Parent == "CoreGui" then
		local ok, res = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
		parent = ok and res or nil
	end
	parent = parent or Players.LocalPlayer:WaitForChild("PlayerGui")
	gui.Parent = parent
	self.Gui = gui

	if opts.Blur then
		self.BlurFx = new("BlurEffect", { Size = 0, Parent = Lighting })
	end

	-- Raiz (não clipa: sombra) → Main (clipa)
	local root = new("Frame", { Name = "Root", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 430), BackgroundTransparency = 1, Parent = gui })
	self.Root = root
	self.Scale = new("UIScale", { Scale = 0.85, Parent = root })
	self.Shadow = new("ImageLabel", { BackgroundTransparency = 1, Image = "rbxassetid://1316045217", ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.55, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(10, 10, 118, 118),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 50, 1, 50), ZIndex = 0, Parent = root })
	local main = new("Frame", { Name = "Main", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ClipsDescendants = true, Parent = root })
	self:_bind(main, "BackgroundColor3", "Background", true); corner(main, 14); self:_stroke(main)
	self.Main = main
	self.BgImage = new("ImageLabel", { Name = "BgImage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop, ZIndex = 0, Visible = false, Parent = main })
	corner(self.BgImage, 14)
	self.BgDim = new("Frame", { Name = "BgDim", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 0, Visible = false, Parent = main })
	self:_bind(self.BgDim, "BackgroundColor3", "Background", true); corner(self.BgDim, 14)
	self:SetBackground(opts.Background or opts.BackgroundImage, opts.BackgroundOpacity, opts.Dim)

	-- Header
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 44), BorderSizePixel = 0, Parent = main })
	self:_bind(header, "BackgroundColor3", "Surface")
	self.Header = header
	local icon
	if opts.Icon then
		icon = self:_icon(header, opts.Icon, 22, "Accent").Frame
		icon.Position = UDim2.new(0, 12, 0.5, -11)
	end
	local tx = icon and 44 or 14
	local hasSub = opts.Subtitle ~= nil and opts.Subtitle ~= ""
	self._hasSub, self._titleY, self._titleX = hasSub, hasSub and -7 or 0, tx
	self.TitleLabel = self:_text(header, opts.Title or "AuroraUI", "Text", 16, Enum.Font.GothamBold)
	self.TitleLabel.Position, self.TitleLabel.Size = UDim2.fromOffset(tx, self._titleY), UDim2.new(1, -tx - 190, 1, 0)
	self.SubtitleLabel = self:_text(header, opts.Subtitle or "", "SubText", 11, Enum.Font.Gotham)
	self.SubtitleLabel.Position, self.SubtitleLabel.Size, self.SubtitleLabel.Visible = UDim2.fromOffset(tx, 25), UDim2.new(1, -tx - 190, 0, 14), hasSub
	self.StatusLabel = self:_text(header, "", "SubText", 12, Enum.Font.Gotham)
	self.StatusLabel.Position, self.StatusLabel.Size, self.StatusLabel.Visible = UDim2.fromOffset(tx, 24), UDim2.new(1, -tx - 80, 0, 14), false
	self._titleX = tx

	local line = new("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1), Visible = opts.AccentLine == true, Parent = header })
	local grad = new("UIGradient", { Parent = line })
	local function paintLine()
		grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, self.Theme.Accent),
			ColorSequenceKeypoint.new(0.5, self.Theme.Accent2), ColorSequenceKeypoint.new(1, self.Theme.Accent) })
	end
	paintLine(); table.insert(self._refreshers, paintLine)
	grad.Offset = Vector2.new(-0.5, 0)
	TweenService:Create(grad, TweenInfo.new(3, EASE.Sine, DIR.InOut, -1, true), { Offset = Vector2.new(0.5, 0) }):Play()

	local function hbtn(iconName, idx, color)
		local b = new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8 - (idx - 1) * 34, 0.5, 0), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = header })
		corner(b, 8)
		local ic = self:_icon(b, iconName, 16, "SubText")
		ic.Frame.AnchorPoint, ic.Frame.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		b.MouseEnter:Connect(function()
			tw(b, { BackgroundTransparency = 0.85, BackgroundColor3 = color or self.Theme.Accent }, 0.15)
			ic:SetColor(color or self.Theme.Text, 0.15)
		end)
		b.MouseLeave:Connect(function()
			tw(b, { BackgroundTransparency = 1 }, 0.15)
			ic:SetColor(self.Theme.SubText, 0.15)
		end)
		return b
	end
	local closeB, minB, maxB, setB, bellB = hbtn("x", 1, self.Theme.Error), hbtn("minus", 2), hbtn("expand", 3), hbtn("gear", 4), hbtn("bell", 5)
	self.SettingsButton, self._hbtns = setB, { maxB, setB, bellB }
	self.Badge = new("TextLabel", { Visible = false, Text = "0", Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = self.Theme.Error, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 2, 0, -2),
		Size = UDim2.fromOffset(14, 14), ZIndex = 3, Parent = bellB })
	corner(self.Badge, 7)
	closeB.Activated:Connect(function() self:Destroy() end)
	minB.Activated:Connect(function() self:Minimize() end)
	maxB.Activated:Connect(function() self:Maximize() end)
	setB.Activated:Connect(function() self:OpenSettings() end)
	bellB.Activated:Connect(function() self:OpenNotificationCenter() end)
	-- arrastar: swipe vertical (touch) minimiza/restaura; soltar perto da borda faz snap
	makeDraggable(self.Maid, header, root, nil, function(d, startPos, touch)
		if touch and d.Y > 80 and math.abs(d.X) < 60 and not self.Minimized then
			tw(root, { Position = startPos }, 0.25)
			self:Minimize(true)
		elseif touch and d.Y < -80 and math.abs(d.X) < 60 and self.Minimized then
			tw(root, { Position = startPos }, 0.25)
			self:Minimize(false)
		else
			self:_snap()
		end
	end)

	-- Corpo: sidebar + conteúdo
	local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1, Parent = main })
	self.Body = body
	self.SideW = 150
	local side = new("Frame", { Name = "Sidebar", Size = UDim2.new(0, self.SideW, 1, 0), BorderSizePixel = 0, Parent = body })
	self:_bind(side, "BackgroundColor3", "Surface"); self.Sidebar = side
	self.TabList = new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
		ScrollBarThickness = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = side })
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.TabList })
	padding(self.TabList, 8, 8, 8, 8)

	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(self.SideW, 0), Size = UDim2.new(1, -self.SideW, 1, 0),
		BackgroundTransparency = 1, Parent = body })
	self.Content = content
	local search = new("TextBox", { PlaceholderText = "Buscar componentes...", Text = "", ClearTextOnFocus = false, Font = Enum.Font.Gotham,
		TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 30), Parent = content })
	self:_bind(search, "BackgroundColor3", "Element"); self:_bind(search, "TextColor3", "Text"); self:_bind(search, "PlaceholderColor3", "SubText")
	corner(search, 8); padding(search, 34, 0, 10, 0); self:_stroke(search)
	self.SearchBox = search
	local sIcon = self:_icon(content, "search", 15, "SubText")
	sIcon.Frame.Position, sIcon.Frame.ZIndex = UDim2.fromOffset(20, 16), 3
	search:GetPropertyChangedSignal("Text"):Connect(function() self:_applySearch() end)
	self.Pages = new("Frame", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1, Parent = content })

	-- Containers de overlay
	self.NotifyHolder = new("Frame", { Size = UDim2.new(0, 300, 1, -24), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })
	self._nLayout = new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.NotifyHolder })
	self:_setNotifyPos(opts.NotifyPosition)
	self.TipLabel = new("TextLabel", { Visible = false, AutomaticSize = Enum.AutomaticSize.XY, Font = Enum.Font.Gotham, TextSize = 12,
		BorderSizePixel = 0, ZIndex = 200, Parent = gui })
	self:_bind(self.TipLabel, "BackgroundColor3", "Surface", true); self:_bind(self.TipLabel, "TextColor3", "Text")
	corner(self.TipLabel, 6); padding(self.TipLabel, 8, 5, 8, 5); self:_stroke(self.TipLabel)

	-- FAB (botão flutuante) para mobile
	if self.Touch or opts.FAB then
		local fab = new("TextButton", { Text = "", AutoButtonColor = false, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(52, 52), ZIndex = 60, Parent = gui })
		self:_bind(fab, "BackgroundColor3", "Accent")
		local fi = self:_icon(fab, "menu", 24, "OnAccent")
		fi.Frame.AnchorPoint, fi.Frame.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		corner(fab, 26); self:_stroke(fab)
		makeDraggable(self.Maid, fab, fab, function() self:Toggle() end)
		self.FAB = fab
	end

	-- Entrada global: tecla de toggle e Ctrl+K
	self.Maid:Add(UIS.InputBegan:Connect(function(i, gp)
		if i.KeyCode == self.ToggleKey and not gp then self:Toggle() end
		if i.KeyCode == Enum.KeyCode.K and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
			self:OpenPalette()
		end
	end))

	-- Efeitos visuais opcionais
	self.Snap = opts.Snap ~= false
	if opts.BackgroundFx then self:SetBackgroundFx(true) end
	if opts.Particles then self:SetParticles(opts.Particles) end

	-- Responsividade
	local cam = workspace.CurrentCamera
	if cam then self.Maid:Add(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() self:_resize() end)) end
	self:_resize()

	-- Animação de abertura
	tw(self.Scale, { Scale = 1 }, 0.5, EASE.Back)
	if self.BlurFx then tw(self.BlurFx, { Size = 12 }, 0.4) end
	self:_sound("open")
	return self
end

-- ---------- helpers internos ----------
function Window:_bind(inst, prop, key, solid)
	inst[prop] = self.Theme[key]
	local glass = false
	if prop == "BackgroundColor3" and not solid and GLASS[key] and inst.BackgroundTransparency < 1 then
		glass = true
		inst.BackgroundTransparency = GLASS[key] * self.Glass
	end
	table.insert(self._themed, { inst, prop, key, glass })
	return inst
end
function Window:_stroke(inst)
	local s = new("UIStroke", { Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst })
	self:_bind(s, "Color", "Stroke")
	return s
end
function Window:_text(parent, text, key, size, font)
	local l = new("TextLabel", { BackgroundTransparency = 1, Text = text, TextSize = size or 14, Font = font or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent })
	self:_bind(l, "TextColor3", key or "Text")
	return l
end
function Window:_sound(kind)
	if not self.Sounds or not SOUNDS[kind] then return end
	local s = new("Sound", { SoundId = SOUNDS[kind], Volume = 0.35, Parent = SoundService })
	s.Ended:Connect(function() s:Destroy() end)
	s:Play()
	task.delay(3, function() if s.Parent then s:Destroy() end end)
end
function Window:_tip(frame, text)
	if not text then return end
	local token = 0
	frame.MouseEnter:Connect(function()
		token += 1
		local my = token
		task.delay(0.5, function()
			if my ~= token then return end
			self.TipLabel.Text = text
			self.TipLabel.Visible = true
			local m = UIS:GetMouseLocation() - GuiService:GetGuiInset()
			self.TipLabel.Position = UDim2.fromOffset(m.X + 14, m.Y + 16)
		end)
	end)
	frame.MouseLeave:Connect(function() token += 1; self.TipLabel.Visible = false end)
end
function Window:_flag(flag, value)
	if flag then
		self.Flags[flag] = value
		self.FlagChanged:Fire(flag, value)
	end
end
function Window:_action(name, fn) table.insert(self.Actions, { Name = name, Fn = fn }) end

-- Cria um ícone: nome vetorial ("home"), "rbxassetid://...", tabela {Image,Offset,Size} ou texto/emoji
function Window:_icon(parent, spec, size, colorKey)
	size, colorKey = size or 18, colorKey or "Text"
	local color = self.Theme[colorKey]
	local obj: any
	local name = IconAliases[spec] or spec
	if type(spec) == "table" or (type(spec) == "string" and string.find(spec, "rbxasset")) then
		local t = type(spec) == "table" and spec or { Image = spec }
		local img = new("ImageLabel", { BackgroundTransparency = 1, Image = t.Image, ImageRectOffset = t.Offset or Vector2.zero,
			ImageRectSize = t.Size or Vector2.zero, Size = UDim2.fromOffset(size, size), ImageColor3 = color, Parent = parent })
		obj = { Frame = img, SetColor = function(_, c, tt) tw(img, { ImageColor3 = c }, tt or 0) end }
	elseif Icons[name] and Icons[name].Image then
		return self:_icon(parent, Icons[name], size, colorKey)
	elseif Icons[name] then
		obj = buildIcon(parent, name, size, color)
	else
		local l = new("TextLabel", { BackgroundTransparency = 1, Text = tostring(spec), Font = Enum.Font.GothamBold, TextSize = size,
			TextColor3 = color, Size = UDim2.fromOffset(size, size), Parent = parent })
		obj = { Frame = l, SetColor = function(_, c, tt) tw(l, { TextColor3 = c }, tt or 0) end }
	end
	obj.ColorKey = colorKey
	table.insert(self._refreshers, function(instant) obj:SetColor(self.Theme[obj.ColorKey], instant and 0 or 0.3) end)
	return obj
end

-- ---------- tema ----------
function Window:_applyTheme(th)
	self.Theme = th
	for i = #self._themed, 1, -1 do
		local b = self._themed[i]
		if not b[1]:IsDescendantOf(self.Gui) then table.remove(self._themed, i)
		else tw(b[1], { [b[2]] = th[b[3]] }, 0.3) end
	end
	for _, f in ipairs(self._refreshers) do pcall(f, true) end
end
function Window:SetTheme(name)
	local th = Themes[name]
	if not th then return end
	self.ThemeName = name
	self:_applyTheme(th)
end
-- Cor de destaque personalizada em runtime (mantém o resto do tema)
function Window:SetAccent(color)
	local th = table.clone(self.Theme)
	local h, s, v = color:ToHSV()
	th.Accent, th.Accent2 = color, Color3.fromHSV((h + 0.08) % 1, s, v)
	th.OnAccent = (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) > 0.6 and Color3.fromHex("#101010") or Color3.new(1, 1, 1)
	self:_applyTheme(th)
end

-- ---------- layout / responsividade ----------
function Window:_resize()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local mx = self.Maximized
	local w, h = math.clamp(vp.X - 24, 300, mx and 940 or 640), math.clamp(vp.Y - (mx and 40 or 90), 220, mx and 640 or 430)
	self.FullSize = UDim2.fromOffset(w, h)
	self._nWidth = math.clamp(vp.X - 24, 220, 300)
	self.NotifyHolder.Size = UDim2.new(0, self._nWidth, 1, -24)
	if not self.Minimized then
		if self._sized then tw(self.Root, { Size = self.FullSize }, 0.3) else self.Root.Size = self.FullSize end
	end
	self._sized = true
	self._autoCompact = w < 520
	self:_applyCompact()
end
function Window:_applyCompact()
	local compact = self.UserCompact or self._autoCompact
	self.Compact = compact
	self.SideW = compact and 56 or 150
	tw(self.Sidebar, { Size = UDim2.new(0, self.SideW, 1, 0) }, 0.3)
	tw(self.Content, { Position = UDim2.fromOffset(self.SideW, 0), Size = UDim2.new(1, -self.SideW, 1, 0) }, 0.3)
	for _, t in ipairs(self.Tabs) do t.Label.Visible = not compact end
end
function Window:SetCompact(b) self.UserCompact = b and true or false; self:_applyCompact() end
function Window:SetScale(n)
	self.UserScale = math.clamp(n, 0.6, 1.5)
	if self.Visible then tw(self.Scale, { Scale = self.UserScale }, 0.2) end
end
function Window:SetScreenshotMode(b) self.Shadow.Visible = not b end
function Window:Maximize(state)
	if state == nil then state = not self.Maximized end
	if self.Minimized then self:Minimize(false) end
	self.Maximized = state and true or false
	self:_resize()
	tw(self.Root, { Position = UDim2.fromScale(0.5, 0.5) }, 0.3)
end

-- Vidro: 0 = sólido, 1 = totalmente translúcido
function Window:SetGlass(n)
	self.Glass = math.clamp(n, 0, 1)
	for _, e in ipairs(self._themed) do
		if e[4] and e[1].Parent then tw(e[1], { BackgroundTransparency = GLASS[e[3]] * self.Glass }, 0.2) end
	end
end
-- Escurecimento sobre a imagem de fundo (0 = nenhum, 1 = totalmente escuro)
function Window:SetBackgroundDim(amount)
	self._dim = math.clamp(amount, 0, 1)
	tw(self.BgDim, { BackgroundTransparency = 1 - self._dim }, 0.2)
end
-- Imagem de fundo: ID numérico, "rbxassetid://...", ou caminho de arquivo (executores com getcustomasset). nil remove.
function Window:SetBackground(id, imageOpacity, dim)
	if type(id) == "string" and id ~= "" and getcustomasset and isfile then
		local ok, isf = pcall(isfile, id)
		if ok and isf then
			local ok2, asset = pcall(getcustomasset, id)
			if ok2 then id = asset end
		end
	end
	if type(id) == "number" or (type(id) == "string" and tonumber(id)) then id = "rbxassetid://" .. tostring(id) end
	local on = type(id) == "string" and id ~= ""
	self.BgImage.Visible, self.BgDim.Visible = on, on
	if on then
		self._imgOp = imageOpacity or self._imgOp or 1
		self._dim = dim or self._dim or 0.4
		self.BgImage.Image = id
		self.BgImage.ImageTransparency = 1 - self._imgOp
		self.BgDim.BackgroundTransparency = 1 - self._dim
	end
	self.Main.BackgroundTransparency = on and 0 or 0.08
end
function Window:SetSubtitle(text)
	self._hasSub = text ~= nil and text ~= ""
	self.SubtitleLabel.Text = text or ""
	self.SubtitleLabel.Visible = self._hasSub and not self.Minimized
	self._titleY = self._hasSub and -7 or 0
	if not self.Minimized then self.TitleLabel.Position = UDim2.fromOffset(self._titleX, self._titleY) end
end

-- ---------- visibilidade / minimizar / destruir ----------
function Window:Toggle(state)
	if state == nil then state = not self.Visible end
	if state == self.Visible then return end
	self.Visible = state
	self:_sound(state and "open" or "close")
	if state then
		self.Root.Visible = true
		tw(self.Scale, { Scale = self.UserScale }, 0.4, EASE.Back)
		if self.BlurFx then tw(self.BlurFx, { Size = 12 }, 0.3) end
	else
		if self.BlurFx then tw(self.BlurFx, { Size = 0 }, 0.3) end
		local t = tw(self.Scale, { Scale = 0.8 }, 0.25, EASE.Back, DIR.In)
		t.Completed:Connect(function() if not self.Visible then self.Root.Visible = false end end)
	end
end

function Window:Minimize(state)
	if state == nil then state = not self.Minimized end
	if state == self.Minimized then return end
	self.Minimized = state
	self:_sound("click")
	if state then
		self.Body.Visible = false
		self.SubtitleLabel.Visible = false
		self.StatusLabel.Visible = true
		for _, b in ipairs(self._hbtns) do b.Visible = false end
		tw(self.TitleLabel, { Position = UDim2.fromOffset(self._titleX, -8), Size = UDim2.new(1, -self._titleX - 80, 1, 0) }, 0.25)
		tw(self.Root, { Size = UDim2.fromOffset(230, 44) }, 0.35)
	else
		self.StatusLabel.Visible = false
		self.SubtitleLabel.Visible = self._hasSub
		for _, b in ipairs(self._hbtns) do b.Visible = true end
		tw(self.TitleLabel, { Position = UDim2.fromOffset(self._titleX, self._titleY), Size = UDim2.new(1, -self._titleX - 190, 1, 0) }, 0.25)
		local t = tw(self.Root, { Size = self.FullSize }, 0.4)
		t.Completed:Connect(function() if not self.Minimized then self.Body.Visible = true end end)
		task.delay(0.12, function() if not self.Minimized then self.Body.Visible = true end end)
	end
end
-- PiP: texto de status mostrado enquanto minimizada
function Window:SetStatus(text) self.StatusLabel.Text = tostring(text) end

function Window:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	self.Destroyed:Fire()
	if self.BlurFx then self.BlurFx:Destroy() end
	local t = tw(self.Scale, { Scale = 0.7 }, 0.25, EASE.Back, DIR.In)
	t.Completed:Connect(function()
		self.Maid:Clean()
		self.Gui:Destroy()
	end)
	task.delay(0.5, function() if self.Gui.Parent then self.Maid:Clean(); self.Gui:Destroy() end end)
end

-- ---------- abas ----------
function Window:CreateTab(name, icon)
	local tab: any = setmetatable({ Window = self, Name = name, Elements = {}, Subs = {} }, Tab)
	local btn = new("TextButton", { Name = name, Size = UDim2.new(1, 0, 0, self.RowH + 4), Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = #self.Tabs + 1, Parent = self.TabList })
	corner(btn, 8)
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 0),
		BorderSizePixel = 0, Parent = btn })
	corner(bar, 2); self:_bind(bar, "BackgroundColor3", "Accent")
	local ic: any
	if icon and icon ~= "" then
		ic = self:_icon(btn, icon, 20, "SubText")
		ic.Frame.Position = UDim2.new(0, 10, 0.5, -10)
	else
		local l = self:_text(btn, string.upper(string.sub(name, 1, 1)), "SubText", 15, Enum.Font.GothamBold)
		l.Size, l.Position, l.TextXAlignment = UDim2.fromOffset(30, 20), UDim2.new(0, 5, 0.5, -10), Enum.TextXAlignment.Center
		ic = { Frame = l, SetColor = function(_, c, tt) tw(l, { TextColor3 = c }, tt or 0) end }
	end
	local label = self:_text(btn, name, "SubText", 14)
	label.Position, label.Size, label.Visible = UDim2.fromOffset(40, 0), UDim2.new(1, -44, 1, 0), not self.Compact
	tab.Button, tab.Label = btn, label

	local page = new("CanvasGroup", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = self.Pages })
	local scroll = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = page })
	self:_bind(scroll, "ScrollBarImageColor3", "Accent")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	padding(scroll, 10, 2, 12, 10)
	tab.Page, tab.Scroll = page, scroll

	tab._render = function(instant)
		local on = self.Current == tab
		local t = instant and 0 or 0.2
		tw(btn, { BackgroundTransparency = on and 0.84 or 1, BackgroundColor3 = self.Theme.Accent }, t)
		tw(bar, { Size = UDim2.fromOffset(3, on and 18 or 0) }, t, EASE.Back)
		tw(label, { TextColor3 = on and self.Theme.Text or self.Theme.SubText }, t)
		ic:SetColor(on and self.Theme.Accent or self.Theme.SubText, t)
	end
	table.insert(self._refreshers, tab._render)
	btn.Activated:Connect(function() self:SelectTab(tab); self:_sound("click") end)
	btn.MouseEnter:Connect(function() if self.Current ~= tab then tw(btn, { BackgroundTransparency = 0.93, BackgroundColor3 = self.Theme.Accent }, 0.15) end end)
	btn.MouseLeave:Connect(function() if self.Current ~= tab then tw(btn, { BackgroundTransparency = 1 }, 0.15) end end)

	table.insert(self.Tabs, tab)
	self:_action("Ir para aba: " .. name, function() self:SelectTab(tab) end)
	if not self.Current then self:SelectTab(tab) end
	return tab
end

function Window:SelectTab(tab)
	if self.Current == tab then return end
	local prev = self.Current
	self.Current = tab
	if prev then prev.Page.Visible = false; prev._render() end
	tab.Page.Visible = true
	tab.Page.GroupTransparency = 1
	tab.Page.Position = UDim2.fromOffset(0, 14)
	tw(tab.Page, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.3)
	tab._render()
	self:_applySearch()
end

function Window:_applySearch()
	local q = string.lower(self.SearchBox.Text)
	local function walk(c)
		for _, e in ipairs(c.Elements) do
			e.Frame.Visible = e.Always or q == "" or (not e.IsSection and string.find(string.lower(e.Name), q, 1, true) ~= nil)
		end
		for _, sub in ipairs(c.Subs or {}) do walk(sub) end
	end
	for _, tab in ipairs(self.Tabs) do walk(tab) end
end

function Window:OpenSettings()
	if not self.SettingsTab then
		local t = self:CreateTab("Configurações", "gear")
		self.SettingsTab = t

		local look = t:CreateSubTab("Aparência")
		look:CreateSection("Tema")
		look:CreateDropdown({ Name = "Tema", Options = ThemeOrder, Default = self.ThemeName, Callback = function(v) self:SetTheme(v) end })
		look:CreateColorPicker({ Name = "Cor de destaque", Default = self.Theme.Accent, Callback = function(c) self:SetAccent(c) end })
		look:CreateSlider({ Name = "Escala da UI", Min = 0.7, Max = 1.3, Default = 1, Increment = 0.05, Callback = function(v) self:SetScale(v) end })
		look:CreateSection("Vidro e fundo")
		look:CreateSlider({ Name = "Transparência (vidro)", Min = 0, Max = 1, Default = self.Glass, Increment = 0.05, Callback = function(v) self:SetGlass(v) end })
		look:CreateTextbox({ Name = "Imagem de fundo (ID)", Placeholder = "ex: 123456789", Callback = function(txt) self:SetBackground(txt ~= "" and txt or nil) end })
		look:CreateSlider({ Name = "Escurecer fundo", Min = 0, Max = 1, Default = self._dim or 0.4, Increment = 0.05, Callback = function(v) self:SetBackgroundDim(v) end })
		look:CreateSection("Efeitos")
		look:CreateDropdown({ Name = "Partículas", Options = { "Desligado", "Float", "Rise", "Snow", "Stars" }, Default = "Desligado",
			Callback = function(v) self:SetParticles(v ~= "Desligado" and { Style = v } or false) end })
		look:CreateToggle({ Name = "Fundo animado", Callback = function(v) self:SetBackgroundFx(v) end })
		look:CreateSection("Janela")
		look:CreateToggle({ Name = "Modo compacto", Callback = function(v) self:SetCompact(v) end })
		look:CreateToggle({ Name = "Snap nas bordas", Default = self.Snap, Callback = function(v) self.Snap = v end })
		look:CreateToggle({ Name = "Modo screenshot (sem sombra)", Callback = function(v) self:SetScreenshotMode(v) end })

		local nt = t:CreateSubTab("Notificações")
		nt:CreateDropdown({ Name = "Posição", Options = { "TopRight", "TopLeft", "TopCenter", "BottomRight", "BottomLeft", "BottomCenter" },
			Default = self.NotifyPos, Callback = function(v) self:_setNotifyPos(v) end })
		nt:CreateToggle({ Name = "Não perturbar (só erros aparecem)", Callback = function(v) self.DND = v end })
		nt:CreateStepper({ Name = "Máx. simultâneas", Min = 1, Max = 8, Default = self.MaxNotifs, Callback = function(v) self.MaxNotifs = v; self:_nNext() end })
		nt:CreateButtonRow({ Buttons = {
			{ Text = "Info", Callback = function() self:Notify({ Title = "Info", Content = "Notificação de teste.", Type = "info" }) end },
			{ Text = "Sucesso", Callback = function() self:Notify({ Title = "Sucesso", Content = "Tudo certo!", Type = "success" }) end },
			{ Text = "Erro", Callback = function() self:Notify({ Title = "Erro", Content = "Algo deu errado.", Type = "error" }) end },
		} })
		nt:CreateButton({ Name = "Abrir central de notificações", Callback = function() self:OpenNotificationCenter() end })

		local sys = t:CreateSubTab("Sistema")
		sys:CreateToggle({ Name = "Sons de interface", Default = self.Sounds, Callback = function(v) self.Sounds = v end })
		sys:CreateToggle({ Name = "HUD (FPS / ping)", Callback = function(v)
			if v then self._hud = self:CreateHud() elseif self._hud then self._hud:Destroy(); self._hud = nil end
		end })
		sys:CreateButton({ Name = "Exportar config (para o console)", Callback = function() self:Log(self:ExportConfig(), "success") end })
		sys:CreateTextbox({ Name = "Importar config (JSON)", Placeholder = "Cole aqui...", Callback = function(txt)
			if txt ~= "" then
				local ok = self:ImportConfig(txt)
				self:Notify({ Title = ok and "Config importada" or "JSON inválido", Type = ok and "success" or "error" })
			end
		end })
		sys:CreateConsole({ Name = "Console interno", Height = 140 })
		sys:CreateButton({ Name = "Destruir UI", Style = "Danger", Callback = function() self:Destroy() end })
	end
	self:SelectTab(self.SettingsTab)
	self:Minimize(false)
end

-- ---------- config (persistência via hook) ----------
function Window:GetConfig() return table.clone(self.Flags) end
function Window:LoadConfig(cfg)
	for flag, v in pairs(cfg or {}) do
		if self.Setters[flag] then self.Setters[flag](v) end
	end
end

-- ---------- log ----------
function Window:Log(text, kind)
	for _, c in ipairs(self.Consoles) do c:Log(text, kind) end
end

-- ---------- notificações v2 ----------
-- Posições, fila (máx. simultâneas), botões de ação, pausa ao passar o mouse, loading,
-- Id para atualizar a mesma notificação, histórico + central, "não perturbar".
local NOTIF_STYLE = {
	info = { "Accent", "info" }, success = { "Success", "check-circle" }, warning = { "Warning", "alert" },
	error = { "Error", "x-circle" }, loading = { "Accent", "loader" },
}
local NOTIF_POS = { TopRight = true, TopLeft = true, TopCenter = true, BottomRight = true, BottomLeft = true, BottomCenter = true }

function Window:_setNotifyPos(pos)
	pos = NOTIF_POS[pos] and pos or "TopRight"
	self.NotifyPos = pos
	local right, left, bottom = string.find(pos, "Right"), string.find(pos, "Left"), string.find(pos, "Bottom")
	self.NotifyHolder.AnchorPoint = Vector2.new(right and 1 or (left and 0 or 0.5), bottom and 1 or 0)
	self.NotifyHolder.Position = UDim2.new(right and 1 or (left and 0 or 0.5), right and -12 or (left and 12 or 0), bottom and 1 or 0, bottom and -12 or 12)
	self._nLayout.VerticalAlignment = bottom and Enum.VerticalAlignment.Bottom or Enum.VerticalAlignment.Top
	self._nLayout.HorizontalAlignment = right and Enum.HorizontalAlignment.Right or (left and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Center)
	self._nSide = right and 1 or (left and -1 or 0)
	self._nBottom = bottom ~= nil
end

function Window:_updateBadge()
	self.Badge.Visible = self.Unread > 0
	self.Badge.Text = self.Unread > 9 and "9+" or tostring(self.Unread)
end

function Window:_nNext()
	while self._nActive < self.MaxNotifs and #self._nQueue > 0 do
		table.remove(self._nQueue, 1)()
	end
end

--[[ Notify{ Title, Content, Type="info|success|warning|error|loading", Duration=4 (0 = fixa),
             Id="chave" (reusa/atualiza), Buttons={{Text,Callback,Primary,Keep}} }
     Retorna handle: :Update{Title,Content,Type,Duration} e :Dismiss() ]]
function Window:Notify(o)
	o = o or {}
	local existing = o.Id and self._nById[o.Id]
	if existing then
		existing:Update(o)
		return existing
	end
	local kind: string = (NOTIF_STYLE[o.Type] and o.Type) or "info"
	table.insert(self.History, 1, { Title = o.Title or "Aviso", Content = o.Content or "", Type = kind, Time = os.date("%H:%M") })
	if #self.History > 50 then table.remove(self.History) end
	if not self._center then self.Unread += 1; self:_updateBadge() end
	self:Log((o.Title or "Aviso") .. ": " .. (o.Content or ""), kind == "loading" and "info" or kind)

	local handle: any = { Closed = false, _done = false }
	function handle:Update() end
	function handle:Dismiss() self.Closed = true end
	if self.DND and kind ~= "error" then handle.Closed = true return handle end
	if o.Id then self._nById[o.Id] = handle end

	local function show()
		if handle.Closed then if o.Id then self._nById[o.Id] = nil end return end
		self._nActive += 1
		local th, side, bottom, width = self.Theme, self._nSide, self._nBottom, self._nWidth
		local actions, content = o.Buttons, o.Content or ""
		local contentW = width - 78
		local function measure(text)
			if not text or text == "" then return 0 end
			return math.min(TextService:GetTextSize(text, 12, Enum.Font.Gotham, Vector2.new(contentW, 1000)).Y, 90)
		end
		local function calcH(text) return math.max(52, 34 + measure(text) + 12 + (actions and 38 or 0) + 3) end

		local holder = new("Frame", { Size = UDim2.new(1, 0, 0, calcH(content)), BackgroundTransparency = 1, LayoutOrder = self._nSeq, Parent = self.NotifyHolder })
		self._nSeq += 1
		local function outPos()
			if side == 0 then return UDim2.fromOffset(0, bottom and 30 or -30) end
			return UDim2.new(side * 1.3, 0, 0, 0)
		end
		local card = new("CanvasGroup", { Position = outPos(), Size = UDim2.fromScale(1, 1), BackgroundColor3 = th.Surface, BorderSizePixel = 0,
			GroupTransparency = 1, Parent = holder })
		corner(card, 12)
		new("UIStroke", { Color = th.Stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })
		local badge = new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(28, 28), BorderSizePixel = 0, Parent = card })
		corner(badge, 14)
		local iconObj: any
		local title = new("TextLabel", { BackgroundTransparency = 1, Text = o.Title or "Aviso", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = th.Text,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(48, 8), Size = UDim2.new(1, -78, 0, 20), Parent = card })
		local msg = new("TextLabel", { BackgroundTransparency = 1, Text = content, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = th.SubText, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(48, 28),
			Size = UDim2.new(1, -78, 0, measure(content)), Parent = card })
		local closeB = new("TextButton", { Text = "", BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(22, 22), Parent = card })
		local cx = self:_icon(closeB, "x", 12, "SubText")
		cx.Frame.AnchorPoint, cx.Frame.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		local prog = new("Frame", { Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0, Parent = card })

		local dismiss: any, startTimer: any
		local token, remaining, startT, ptween, timed, spin = 0, 0, 0, nil, false, nil

		local function applyStyle()
			local st = NOTIF_STYLE[kind]
			local c = self.Theme[st[1]]
			badge.BackgroundColor3, badge.BackgroundTransparency = c, 0.82
			prog.BackgroundColor3 = c
			if spin then spin:Cancel(); spin = nil end
			if iconObj then iconObj.Frame:Destroy() end
			iconObj = self:_icon(badge, st[2], 18, st[1])
			iconObj.Frame.AnchorPoint, iconObj.Frame.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			if kind == "loading" then
				spin = TweenService:Create(iconObj.Frame, TweenInfo.new(0.9, EASE.Linear, DIR.Out, -1), { Rotation = 360 })
				spin:Play()
			end
		end
		applyStyle()

		if actions then
			local row = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 48, 1, -40), Size = UDim2.new(1, -60, 0, 28), Parent = card })
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = row })
			for _, b in ipairs(actions) do
				local bt = new("TextButton", { Text = b.Text, Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false, BorderSizePixel = 0,
					AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Parent = row,
					BackgroundColor3 = b.Primary and th.Accent or th.Element, TextColor3 = b.Primary and th.OnAccent or th.Text })
				corner(bt, 6); padding(bt, 12, 0, 12, 0)
				bt.Activated:Connect(function()
					call(b.Callback, handle)
					if not b.Keep then dismiss() end
				end)
			end
		end

		startTimer = function(t, reset)
			token += 1
			local my = token
			remaining, startT = t, tick()
			if reset then prog.Size = UDim2.new(1, 0, 0, 3) end
			ptween = tw(prog, { Size = UDim2.new(0, 0, 0, 3) }, t, EASE.Linear)
			task.delay(t, function() if my == token and not handle.Closed then dismiss() end end)
		end
		local function setDuration(d)
			token += 1
			if ptween then ptween:Cancel() end
			timed = d > 0
			prog.Visible = timed
			if timed then startTimer(d, true) end
		end

		dismiss = function()
			if handle.Closed and handle._done then return end
			handle.Closed, handle._done = true, true
			token += 1
			if spin then spin:Cancel() end
			if o.Id then self._nById[o.Id] = nil end
			tw(card, { Position = outPos(), GroupTransparency = 1 }, 0.3, EASE.Quint, DIR.In).Completed:Connect(function()
				tw(holder, { Size = UDim2.new(1, 0, 0, 0) }, 0.2).Completed:Connect(function() holder:Destroy() end)
			end)
			self._nActive -= 1
			self:_nNext()
		end
		closeB.Activated:Connect(dismiss)

		card.MouseEnter:Connect(function()
			if timed and not handle.Closed then
				token += 1
				if ptween then ptween:Cancel() end
				remaining -= tick() - startT
			end
		end)
		card.MouseLeave:Connect(function()
			if timed and not handle.Closed then startTimer(math.max(remaining, 1), false) end
		end)

		function handle:Update(u)
			if self.Closed then return end
			if u.Title then title.Text = u.Title end
			if u.Content then
				content = u.Content
				msg.Text = content
				msg.Size = UDim2.new(1, -78, 0, measure(content))
				tw(holder, { Size = UDim2.new(1, 0, 0, calcH(content)) }, 0.2)
			end
			if u.Type and NOTIF_STYLE[u.Type] then kind = u.Type; applyStyle() end
			if u.Duration ~= nil or u.Type then
				local d = u.Duration
				if d == nil then d = kind == "loading" and 0 or 4 end
				setDuration(d)
			end
		end
		function handle:Dismiss() dismiss() end

		tw(card, { Position = UDim2.new(), GroupTransparency = 0 }, 0.45, EASE.Back)
		self:_sound("click")
		local d = o.Duration
		if d == nil then d = (kind == "loading" or o.Sticky) and 0 or 4 end
		setDuration(d)
	end

	if self._nActive >= self.MaxNotifs then table.insert(self._nQueue, show) else show() end
	return handle
end

-- Central de notificações (histórico)
function Window:OpenNotificationCenter()
	if self._center then return end
	self.Unread = 0
	self:_updateBadge()
	local vp = self.Gui.AbsoluteSize
	local ov = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Text = "",
		AutoButtonColor = false, ZIndex = 110, Parent = self.Gui })
	self._center = ov
	tw(ov, { BackgroundTransparency = 0.5 }, 0.2)
	local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Active = true, BorderSizePixel = 0,
		Size = UDim2.fromOffset(math.min(380, vp.X - 24), math.min(440, vp.Y - 80)), Parent = ov })
	self:_bind(box, "BackgroundColor3", "Surface", true); corner(box, 12); self:_stroke(box)
	local t = self:_text(box, "Notificações", "Text", 16, Enum.Font.GothamBold)
	t.Position, t.Size = UDim2.fromOffset(14, 10), UDim2.new(1, -150, 0, 24)
	local function close() ov:Destroy(); self._center = nil end
	local clear = new("TextButton", { Text = "Limpar", Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(60, 24), Parent = box })
	self:_bind(clear, "BackgroundColor3", "Element"); self:_bind(clear, "TextColor3", "Text"); corner(clear, 6)
	local dnd = new("TextButton", { Font = Enum.Font.Gotham, TextSize = 12, AutoButtonColor = false, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 42),
		Size = UDim2.new(1, -28, 0, 26), Parent = box })
	self:_bind(dnd, "BackgroundColor3", "Element"); self:_bind(dnd, "TextColor3", "Text"); corner(dnd, 6)
	local function renderDnd() dnd.Text = self.DND and "🔕  Não perturbar: LIGADO" or "🔔  Não perturbar: desligado" end
	renderDnd()
	dnd.Activated:Connect(function() self.DND = not self.DND; renderDnd() end)
	local list = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, Position = UDim2.fromOffset(14, 76),
		Size = UDim2.new(1, -28, 1, -88), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = box })
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local function build()
		for _, c in ipairs(list:GetChildren()) do if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end end
		if #self.History == 0 then
			local e = self:_text(list, "Nenhuma notificação.", "SubText", 13, Enum.Font.Gotham)
			e.Size = UDim2.new(1, 0, 0, 30)
			return
		end
		for i, h in ipairs(self.History) do
			local st = NOTIF_STYLE[h.Type] or NOTIF_STYLE.info
			local e = new("Frame", { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, LayoutOrder = i, Parent = list })
			self:_bind(e, "BackgroundColor3", "Element"); corner(e, 8); padding(e, 10, 8, 10, 8)
			new("UIListLayout", { Padding = UDim.new(0, 2), Parent = e })
			local hr = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Parent = e })
			local hi = self:_icon(hr, st[2], 15, st[1])
			hi.Frame.Position = UDim2.fromOffset(0, 1)
			local a = self:_text(hr, h.Title .. "   ·   " .. h.Time, st[1], 13, Enum.Font.GothamBold)
			a.Position, a.Size = UDim2.fromOffset(22, 0), UDim2.new(1, -22, 1, 0)
			if h.Content ~= "" then
				local b = self:_text(e, h.Content, "SubText", 12, Enum.Font.Gotham)
				b.Size, b.AutomaticSize, b.TextWrapped, b.TextTruncate = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y, true, Enum.TextTruncate.None
			end
		end
	end
	build()
	clear.Activated:Connect(function() table.clear(self.History); build() end)
	ov.Activated:Connect(close)
end

-- ---------- modal ----------
function Window:Dialog(o)
	local ov = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, ZIndex = 100, Parent = self.Gui })
	tw(ov, { BackgroundTransparency = 0.5 }, 0.2)
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 800
	local box = new("CanvasGroup", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(math.min(340, vp - 40), 0),
		AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, GroupTransparency = 1, Parent = ov })
	self:_bind(box, "BackgroundColor3", "Surface", true); corner(box, 12); self:_stroke(box); padding(box, 16, 16, 16, 16)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
	local t = self:_text(box, o.Title or "Confirmar", "Text", 17, Enum.Font.GothamBold)
	t.Size, t.LayoutOrder = UDim2.new(1, 0, 0, 22), 1
	local c = self:_text(box, o.Content or "", "SubText", 13, Enum.Font.Gotham)
	c.Size, c.AutomaticSize, c.TextWrapped, c.TextTruncate, c.LayoutOrder = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y, true, Enum.TextTruncate.None, 2
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, self.RowH), BackgroundTransparency = 1, LayoutOrder = 3, Parent = box })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8), Parent = row })
	local function close()
		tw(ov, { BackgroundTransparency = 1 }, 0.2)
		tw(box, { GroupTransparency = 1 }, 0.2).Completed:Connect(function() ov:Destroy() end)
	end
	for idx, b in ipairs(o.Buttons or { { Text = "OK", Primary = true } }) do
		local bt = new("TextButton", { Text = b.Text, Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = false, BorderSizePixel = 0,
			Size = UDim2.new(0, 96, 1, 0), LayoutOrder = idx, Parent = row })
		corner(bt, 8)
		self:_bind(bt, "BackgroundColor3", b.Primary and "Accent" or "Element")
		self:_bind(bt, "TextColor3", b.Primary and "OnAccent" or "Text")
		bt.Activated:Connect(function() close(); call(b.Callback) end)
	end
	tw(box, { GroupTransparency = 0 }, 0.25)
	return { Close = close }
end

-- ---------- context menu ----------
function Window:ContextMenu(items)
	local m = UIS:GetMouseLocation() - GuiService:GetGuiInset()
	local blocker = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 150, Parent = self.Gui })
	local menu = new("Frame", { Position = UDim2.fromOffset(m.X, m.Y), Size = UDim2.fromOffset(170, #items * 30 + 8), BorderSizePixel = 0, Parent = blocker })
	self:_bind(menu, "BackgroundColor3", "Surface", true); corner(menu, 8); self:_stroke(menu); padding(menu, 4, 4, 4, 4)
	new("UIListLayout", { Parent = menu })
	for _, it in ipairs(items) do
		local b = new("TextButton", { Text = it.Name, Font = Enum.Font.Gotham, TextSize = 13, AutoButtonColor = false, BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30), Parent = menu })
		corner(b, 6); self:_bind(b, "TextColor3", "Text")
		b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.8; b.BackgroundColor3 = self.Theme.Accent end)
		b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
		b.Activated:Connect(function() blocker:Destroy(); call(it.Callback) end)
	end
	blocker.Activated:Connect(function() blocker:Destroy() end)
end

-- ---------- command palette (Ctrl+K) ----------
function Window:OpenPalette()
	if self._palette then return end
	local ov = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5,
		Text = "", AutoButtonColor = false, ZIndex = 120, Parent = self.Gui })
	self._palette = ov
	local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 80), Size = UDim2.fromOffset(380, 250),
		BorderSizePixel = 0, Parent = ov })
	box.Size = UDim2.new(0, math.min(380, (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 800) - 24), 0, 250)
	self:_bind(box, "BackgroundColor3", "Surface", true); corner(box, 12); self:_stroke(box)
	local input = new("TextBox", { PlaceholderText = "Digite uma ação...", Text = "", ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 34), Parent = box })
	self:_bind(input, "BackgroundColor3", "Element"); self:_bind(input, "TextColor3", "Text"); self:_bind(input, "PlaceholderColor3", "SubText")
	corner(input, 8); padding(input, 10, 0, 10, 0)
	local list = new("ScrollingFrame", { Position = UDim2.fromOffset(10, 52), Size = UDim2.new(1, -20, 1, -62), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = box })
	new("UIListLayout", { Padding = UDim.new(0, 2), Parent = list })
	local function close() ov:Destroy(); self._palette = nil end
	local function refresh()
		for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
		local q, n = string.lower(input.Text), 0
		for _, a in ipairs(self.Actions) do
			if q == "" or string.find(string.lower(a.Name), q, 1, true) then
				n += 1
				if n > 30 then break end
				local b = new("TextButton", { Text = a.Name, Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
					AutoButtonColor = false, BackgroundTransparency = n == 1 and 0.85 or 1, BackgroundColor3 = self.Theme.Accent,
					Size = UDim2.new(1, 0, 0, 30), Parent = list })
				corner(b, 6); padding(b, 10, 0, 0, 0); self:_bind(b, "TextColor3", "Text")
				b.Activated:Connect(function() close(); call(a.Fn) end)
			end
		end
	end
	input:GetPropertyChangedSignal("Text"):Connect(refresh)
	input.FocusLost:Connect(function(enter)
		if enter then
			local first = list:FindFirstChildOfClass("TextButton")
			if first then
				local act
				for _, x in ipairs(self.Actions) do
					if x.Name == first.Text then act = x break end
				end
				close()
				if act then call(act.Fn) end
				return
			end
		end
		task.delay(0.15, function() if self._palette == ov then close() end end)
	end)
	ov.Activated:Connect(close)
	refresh()
	input:CaptureFocus()
end

----------------------------------------------------------------------
-- 4. COMPONENTES (Tab)
----------------------------------------------------------------------
local function hit(parent)
	return new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = parent })
end

function Tab:_row(name, h, tooltip, menu, isSection)
	local w = self.Window
	local f = new("Frame", { Name = name, Size = UDim2.new(1, 0, 0, h or w.RowH), BorderSizePixel = 0, LayoutOrder = #self.Elements + 1, Parent = self.Scroll })
	w:_bind(f, "BackgroundColor3", "Element"); corner(f, 8); w:_stroke(f)
	table.insert(self.Elements, { Frame = f, Name = name, IsSection = isSection })
	w:_tip(f, tooltip)
	if menu then
		f.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton2 then w:ContextMenu(menu)
			elseif i.UserInputType == Enum.UserInputType.Touch then
				local start = tick()
				local c; c = i:GetPropertyChangedSignal("UserInputState"):Connect(function()
					if i.UserInputState == Enum.UserInputState.End then c:Disconnect() end
				end)
				task.delay(0.55, function() if i.UserInputState ~= Enum.UserInputState.End and tick() - start >= 0.5 then w:ContextMenu(menu) end end)
			end
		end)
	end
	return f
end

local function label(self, row, text, wfrac, icon)
	local l = self.Window:_text(row, text)
	l.Position, l.Size = UDim2.fromOffset(12, 0), UDim2.new(wfrac or 1, -24, 1, 0)
	if icon then
		local ic = self.Window:_icon(row, icon, 16, "Accent")
		ic.Frame.AnchorPoint, ic.Frame.Position = Vector2.new(0, 0.5), UDim2.new(0, 12, 0.5, 0)
		l.Position, l.Size = UDim2.fromOffset(36, 0), UDim2.new(wfrac or 1, -48, 1, 0)
	end
	return l
end

function Tab:CreateSection(name)
	local w = self.Window
	local f = new("Frame", { Name = name, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = #self.Elements + 1, Parent = self.Scroll })
	table.insert(self.Elements, { Frame = f, Name = name, IsSection = true })
	local pip = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 2), Size = UDim2.fromOffset(3, 14), BorderSizePixel = 0, Parent = f })
	corner(pip, 2); w:_bind(pip, "BackgroundColor3", "Accent")
	local l = w:_text(f, name, "Text", 15, Enum.Font.GothamBold)
	l.Position, l.Size = UDim2.fromOffset(14, 4), UDim2.new(1, -18, 0, 22)
	return { Frame = f }
end

function Tab:CreateDivider()
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, LayoutOrder = #self.Elements + 1, Parent = self.Scroll })
	self.Window:_bind(f, "BackgroundColor3", "Stroke")
	table.insert(self.Elements, { Frame = f, Name = "", IsSection = true })
	return { Frame = f }
end

function Tab:CreateLabel(o)
	if type(o) == "string" then o = { Name = o } end
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	local l = label(self, row, o.Name, nil, o.Icon)
	local obj: any = { Frame = row }
	function obj:Set(t) l.Text = t end
	return obj
end

function Tab:CreateParagraph(o)
	local w = self.Window
	local row = self:_row(o.Title or "", 10, o.Tooltip)
	row.AutomaticSize, row.Size = Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 0)
	padding(row, 12, 10, 12, 10)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	local t = w:_text(row, o.Title or "", "Text", 14, Enum.Font.GothamBold)
	t.Size, t.LayoutOrder = UDim2.new(1, 0, 0, 18), 1
	local c = w:_text(row, o.Content or "", "SubText", 13, Enum.Font.Gotham)
	c.Size, c.AutomaticSize, c.TextWrapped, c.TextTruncate, c.LayoutOrder = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y, true, Enum.TextTruncate.None, 2
	local obj: any = { Frame = row }
	function obj:Set(title, content) t.Text = title; c.Text = content or c.Text end
	return obj
end

function Tab:CreateCard(o)
	local w = self.Window
	local row = self:_row(o.Title or "Card", 84, o.Tooltip, o.Menu)
	local img = new("ImageLabel", { BackgroundTransparency = 1, Image = o.Image or "", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(68, 68),
		ScaleType = Enum.ScaleType.Crop, Parent = row })
	w:_bind(img, "BackgroundColor3", "Stroke"); img.BackgroundTransparency = 0; corner(img, 8)
	local t = w:_text(row, o.Title or "", "Text", 15, Enum.Font.GothamBold)
	t.Position, t.Size = UDim2.fromOffset(88, 12), UDim2.new(1, -100, 0, 20)
	local d = w:_text(row, o.Description or "", "SubText", 12, Enum.Font.Gotham)
	d.Position, d.Size, d.TextWrapped, d.TextYAlignment, d.TextTruncate = UDim2.fromOffset(88, 34), UDim2.new(1, -100, 0, 40), true, Enum.TextYAlignment.Top, Enum.TextTruncate.AtEnd
	if o.Callback then
		local b = hit(row)
		b.Activated:Connect(function() call(o.Callback) end)
	end
	return { Frame = row }
end

function Tab:CreateButton(o)
	local w = self.Window
	local danger = o.Style == "Danger"
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	local key = danger and "Error" or "Element"
	local l = label(self, row, o.Name)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.Size, l.Position = UDim2.new(1, -24, 1, 0), UDim2.fromOffset(12, 0)
	if o.Icon then
		local ic = w:_icon(row, o.Icon, 18, danger and "OnAccent" or "Accent")
		ic.Frame.Position = UDim2.new(0, 12, 0.5, -9)
	end
	if danger then w:_bind(row, "BackgroundColor3", "Error"); w:_bind(l, "TextColor3", "OnAccent") end
	local b = hit(row)
	b.MouseEnter:Connect(function() if not danger then tw(row, { BackgroundColor3 = w.Theme.ElementHover }, 0.15) end end)
	b.MouseLeave:Connect(function() if not danger then tw(row, { BackgroundColor3 = w.Theme.Element }, 0.15) end end)
	b.Activated:Connect(function()
		w:_sound("click")
		local s = row:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = row })
		s.Scale = 0.97
		tw(s, { Scale = 1 }, 0.25, EASE.Back)
		call(o.Callback)
	end)
	w:_action("Executar: " .. o.Name, function() call(o.Callback) end)
	local obj: any = { Frame = row }
	function obj:SetText(t) l.Text = t end
	return obj
end

local function makeSwitchLike(self, o, shape)
	local w = self.Window
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	label(self, row, o.Name, 1, o.Icon).Size = UDim2.new(1, -70, 1, 0)
	local box, knob
	if shape == "toggle" then
		box = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(40, 20), BorderSizePixel = 0, Parent = row })
		corner(box, 10)
		knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = box })
		corner(knob, 8)
	else
		box = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(22, 22), BorderSizePixel = 0, Parent = row })
		corner(box, 6)
		knob = w:_icon(box, "check", 14, "OnAccent").Frame
		knob.AnchorPoint, knob.Position, knob.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(0, 0)
	end
	local obj: any = { Value = o.Default == true }
	local function render(instant)
		local on, t = obj.Value, instant and 0 or 0.2
		if shape == "toggle" then
			tw(box, { BackgroundColor3 = on and w.Theme.Accent or w.Theme.Stroke }, t)
			tw(knob, { Position = on and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) }, t, EASE.Back)
		else
			tw(box, { BackgroundColor3 = on and w.Theme.Accent or w.Theme.Stroke }, t)
			tw(knob, { Size = on and UDim2.fromOffset(14, 14) or UDim2.fromOffset(0, 0) }, t, EASE.Back)
		end
	end
	function obj:Set(v, silent)
		self.Value = v and true or false
		render()
		w:_flag(o.Flag, self.Value)
		if not silent then call(o.Callback, self.Value) end
	end
	function obj:Get() return self.Value end
	render(true)
	table.insert(w._refreshers, render)
	local b = hit(row)
	b.Activated:Connect(function() w:_sound("click"); obj:Set(not obj.Value) end)
	if o.Flag then w.Flags[o.Flag] = obj.Value; w.Setters[o.Flag] = function(v) obj:Set(v) end end
	w:_action("Alternar: " .. o.Name, function() obj:Set(not obj.Value) end)
	obj.Frame = row
	return obj
end
function Tab:CreateToggle(o) return makeSwitchLike(self, o, "toggle") end
function Tab:CreateCheckbox(o) return makeSwitchLike(self, o, "checkbox") end

function Tab:CreateSlider(o)
	local w = self.Window
	local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	local l = w:_text(row, o.Name)
	l.Position, l.Size = UDim2.fromOffset(12, 0), UDim2.new(0.42, -12, 1, 0)
	local box = new("TextBox", { Text = "", Font = Enum.Font.GothamMedium, TextSize = 12, ClearTextOnFocus = false, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.42, 0, 0.5, 0), Size = UDim2.fromOffset(54, 22), Parent = row })
	w:_bind(box, "BackgroundColor3", "Background"); w:_bind(box, "TextColor3", "Text"); corner(box, 6)
	local hitbar = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.42, 64, 0.5, 0),
		Size = UDim2.new(0.58, -76, 0, 22), Parent = row })
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 6), BorderSizePixel = 0, Parent = hitbar })
	w:_bind(bar, "BackgroundColor3", "Stroke"); corner(bar, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = bar })
	corner(fill, 3)
	local fg = new("UIGradient", { Parent = fill })
	local function paint() fg.Color = ColorSequence.new(w.Theme.Accent, w.Theme.Accent2) end
	paint(); table.insert(w._refreshers, paint)
	local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = bar })
	corner(knob, 7)
	local obj: any = { Value = o.Default or min }
	local decimals = inc < 1 and 2 or 0
	local function fmt(v) return string.format("%." .. decimals .. "f", v) end
	local function render(fast)
		local r = (obj.Value - min) / (max - min)
		local t = fast and 0.05 or 0.15
		tw(fill, { Size = UDim2.fromScale(r, 1) }, t)
		tw(knob, { Position = UDim2.fromScale(r, 0.5) }, t)
		box.Text = fmt(obj.Value) .. (o.Suffix or "")
	end
	function obj:Set(v, silent)
		v = math.clamp(math.round(v / inc) * inc, min, max)
		if v == self.Value and silent ~= nil then return end
		self.Value = v
		render(true)
		w:_flag(o.Flag, v)
		if not silent then call(o.Callback, v) end
	end
	function obj:Get() return self.Value end
	bindDrag(w.Maid, hitbar, function(rx) obj:Set(min + rx * (max - min)) end)
	box.FocusLost:Connect(function()
		local n = tonumber(string.match(box.Text, "-?%d+%.?%d*"))
		if n then obj:Set(n) else render() end
	end)
	render(true)
	if o.Flag then w.Flags[o.Flag] = obj.Value; w.Setters[o.Flag] = function(v) obj:Set(v) end end
	obj.Frame = row
	return obj
end

function Tab:CreateTextbox(o)
	local w = self.Window
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	label(self, row, o.Name, 0.5, o.Icon)
	local tb = new("TextBox", { Text = o.Default or "", PlaceholderText = o.Placeholder or "Digite...", ClearTextOnFocus = false, Font = Enum.Font.Gotham,
		TextSize = 13, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0.5, -12, 1, -10), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
	w:_bind(tb, "BackgroundColor3", "Background"); w:_bind(tb, "TextColor3", "Text"); w:_bind(tb, "PlaceholderColor3", "SubText")
	corner(tb, 6); padding(tb, 8, 0, 8, 0)
	local st = w:_stroke(tb)
	tb.Focused:Connect(function() tw(st, { Color = w.Theme.Accent }, 0.15) end)
	local obj: any = { Value = tb.Text }
	function obj:Set(v, silent)
		tb.Text = tostring(v); self.Value = tb.Text
		w:_flag(o.Flag, self.Value)
		if not silent then call(o.Callback, self.Value) end
	end
	function obj:Get() return self.Value end
	tb.FocusLost:Connect(function()
		local txt = tb.Text
		if o.Numeric then txt = string.match(txt, "-?%d+%.?%d*") or ""; tb.Text = txt end
		if o.Validate and not o.Validate(txt) then
			tw(st, { Color = w.Theme.Error }, 0.1)
			task.delay(0.8, function() tw(st, { Color = w.Theme.Stroke }, 0.3) end)
			tb.Text = obj.Value
			return
		end
		tw(st, { Color = w.Theme.Stroke }, 0.15)
		obj.Value = txt
		w:_flag(o.Flag, txt)
		call(o.Callback, txt)
	end)
	if o.Flag then w.Flags[o.Flag] = obj.Value; w.Setters[o.Flag] = function(v) obj:Set(v) end end
	obj.Frame = row
	return obj
end

function Tab:CreateKeybind(o)
	local w = self.Window
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	label(self, row, o.Name, 0.6, o.Icon)
	local b = new("TextButton", { Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(90, w.RowH - 10), Parent = row })
	w:_bind(b, "BackgroundColor3", "Background"); w:_bind(b, "TextColor3", "Accent"); corner(b, 6)
	local obj: any = { Key = o.Default, Listening = false }
	local function render() b.Text = obj.Listening and "..." or (obj.Key and obj.Key.Name or "Nenhuma") end
	function obj:Set(key, silent)
		if type(key) == "string" then key = Enum.KeyCode[key] end
		self.Key, self.Listening = key, false
		render()
		w:_flag(o.Flag, key and key.Name or nil)
		if not silent then call(o.Changed, key) end
	end
	function obj:Get() return self.Key end
	b.Activated:Connect(function() obj.Listening = true; render() end)
	w.Maid:Add(UIS.InputBegan:Connect(function(i, gp)
		if obj.Listening then
			if i.UserInputType == Enum.UserInputType.Keyboard then
				if i.KeyCode == Enum.KeyCode.Escape then obj.Listening = false; render()
				elseif i.KeyCode == Enum.KeyCode.Backspace then obj:Set(nil)
				else obj:Set(i.KeyCode) end
			end
		elseif not gp and obj.Key and i.KeyCode == obj.Key then
			call(o.Callback, obj.Key)
		end
	end))
	render()
	if o.Flag then w.Flags[o.Flag] = obj.Key and obj.Key.Name or nil; w.Setters[o.Flag] = function(v) obj:Set(v) end end
	obj.Frame = row
	return obj
end

function Tab:CreateProgressBar(o)
	local w = self.Window
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	row.Size = UDim2.new(1, 0, 0, w.RowH + 12)
	local l = w:_text(row, o.Name)
	l.Position, l.Size = UDim2.fromOffset(12, 6), UDim2.new(1, -80, 0, 18)
	local pct = w:_text(row, "0%", "SubText", 12)
	pct.AnchorPoint, pct.Position, pct.Size, pct.TextXAlignment = Vector2.new(1, 0), UDim2.new(1, -12, 0, 6), UDim2.fromOffset(60, 18), Enum.TextXAlignment.Right
	local bar = new("Frame", { Position = UDim2.new(0, 12, 1, -18), Size = UDim2.new(1, -24, 0, 8), BorderSizePixel = 0, Parent = row })
	w:_bind(bar, "BackgroundColor3", "Stroke"); corner(bar, 4)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = bar })
	corner(fill, 4)
	local fg = new("UIGradient", { Parent = fill })
	local function paint() fg.Color = ColorSequence.new(w.Theme.Accent, w.Theme.Accent2) end
	paint(); table.insert(w._refreshers, paint)
	local obj: any = { Value = 0 }
	function obj:Set(v)
		v = math.clamp(v, 0, 1)
		self.Value = v
		tw(fill, { Size = UDim2.fromScale(v, 1) }, 0.4)
		pct.Text = tostring(math.floor(v * 100 + 0.5)) .. "%"
		w:_flag(o.Flag, v)
	end
	obj:Set(o.Value or 0)
	obj.Frame = row
	return obj
end

function Tab:CreateRadio(o)
	local w = self.Window
	local n = #o.Options
	local row = self:_row(o.Name, 30 + n * 30 + 6, o.Tooltip, o.Menu)
	local l = w:_text(row, o.Name)
	l.Position, l.Size = UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 20)
	local obj: any = { Value = o.Default or o.Options[1], _dots = {} }
	local function render(instant)
		for name, d in pairs(obj._dots) do
			local on = name == obj.Value
			tw(d.ring, { BackgroundColor3 = on and w.Theme.Accent or w.Theme.Stroke }, instant and 0 or 0.2)
			tw(d.dot, { Size = on and UDim2.fromOffset(8, 8) or UDim2.fromOffset(0, 0) }, instant and 0 or 0.2, EASE.Back)
		end
	end
	for i, name in ipairs(o.Options) do
		local b = new("TextButton", { Text = "", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 30 + (i - 1) * 30), Size = UDim2.new(1, -24, 0, 28), Parent = row })
		local ring = new("Frame", { Position = UDim2.fromOffset(0, 5), Size = UDim2.fromOffset(18, 18), BorderSizePixel = 0, Parent = b })
		corner(ring, 9)
		local dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = ring })
		corner(dot, 4)
		local t = w:_text(b, name, "Text", 13, Enum.Font.Gotham)
		t.Position, t.Size = UDim2.fromOffset(28, 0), UDim2.new(1, -28, 1, 0)
		obj._dots[name] = { ring = ring, dot = dot }
		b.Activated:Connect(function() obj:Set(name) end)
	end
	function obj:Set(v, silent)
		self.Value = v; render()
		w:_flag(o.Flag, v)
		if not silent then call(o.Callback, v) end
	end
	function obj:Get() return self.Value end
	render(true)
	table.insert(w._refreshers, render)
	if o.Flag then w.Flags[o.Flag] = obj.Value; w.Setters[o.Flag] = function(v) obj:Set(v) end end
	obj.Frame = row
	return obj
end

function Tab:CreateDropdown(o)
	local w = self.Window
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	row.ClipsDescendants = true
	local baseH = w.RowH
	local l = label(self, row, o.Name, 0.5, o.Icon)
	local valueL = w:_text(row, "", "Accent", 13, Enum.Font.GothamMedium)
	valueL.AnchorPoint, valueL.Position, valueL.Size, valueL.TextXAlignment = Vector2.new(1, 0), UDim2.new(1, -30, 0, 0), UDim2.new(0.5, -30, 0, baseH), Enum.TextXAlignment.Right
	local arrow = w:_icon(row, "chevron-down", 16, "SubText").Frame
	arrow.AnchorPoint, arrow.Position = Vector2.new(1, 0.5), UDim2.new(1, -10, 0, baseH // 2)
	local head = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, baseH), ZIndex = 2, Parent = row })

	local searchBox
	local top = 0
	if o.Searchable then
		searchBox = new("TextBox", { PlaceholderText = "Buscar...", Text = "", ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 12, BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, baseH), Size = UDim2.new(1, -16, 0, 26), Parent = row })
		w:_bind(searchBox, "BackgroundColor3", "Background"); w:_bind(searchBox, "TextColor3", "Text"); w:_bind(searchBox, "PlaceholderColor3", "SubText")
		corner(searchBox, 6); padding(searchBox, 8, 0, 8, 0)
		top = 32
	end
	local list = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, Position = UDim2.fromOffset(8, baseH + top),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = row })
	new("UIListLayout", { Padding = UDim.new(0, 2), Parent = list })
	local obj: any = { Options = o.Options or {}, Multi = o.Multi, Open = false, Value = o.Multi and {} or nil }
	local buttons = {}
	local function selected(name)
		if obj.Multi then return table.find(obj.Value, name) ~= nil end
		return obj.Value == name
	end
	local function renderValue()
		if obj.Multi then valueL.Text = #obj.Value == 0 and "Nenhum" or table.concat(obj.Value, ", ")
		else valueL.Text = obj.Value or "Selecione" end
		for name, b in pairs(buttons) do
			local on = selected(name)
			b.BackgroundTransparency = on and 0.8 or 1
			b.TextColor3 = on and w.Theme.Accent or w.Theme.Text
		end
	end
	local function listH() return math.min(#obj.Options, 5) * 30 end
	local function setOpen(v)
		obj.Open = v
		list.Size = UDim2.new(1, -16, 0, listH())
		tw(row, { Size = UDim2.new(1, 0, 0, v and (baseH + top + listH() + 8) or baseH) }, 0.3)
		tw(arrow, { Rotation = v and 180 or 0 }, 0.3)
	end
	local function build()
		for _, b in pairs(buttons) do b:Destroy() end
		table.clear(buttons)
		for i, name in ipairs(obj.Options) do
			local b = new("TextButton", { Text = "  " .. name, Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false,
				BackgroundColor3 = w.Theme.Accent, BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 28), LayoutOrder = i, Parent = list })
			corner(b, 6)
			buttons[name] = b
			b.Activated:Connect(function() w:_sound("click"); obj:Set(name, nil, true) end)
		end
		renderValue()
	end
	function obj:Set(v, silent, fromClick)
		if self.Multi then
			if fromClick then
				local i = table.find(self.Value, v)
				if i then table.remove(self.Value, i) else table.insert(self.Value, v) end
			else self.Value = type(v) == "table" and v or {} end
		else
			self.Value = v
			if fromClick then setOpen(false) end
		end
		renderValue()
		w:_flag(o.Flag, self.Value)
		if not silent then call(o.Callback, self.Value) end
	end
	function obj:Get() return self.Value end
	function obj:Refresh(opts) self.Options = opts; build(); if self.Open then setOpen(true) end end
	head.Activated:Connect(function() setOpen(not obj.Open) end)
	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local q = string.lower(searchBox.Text)
			for name, b in pairs(buttons) do b.Visible = q == "" or string.find(string.lower(name), q, 1, true) ~= nil end
		end)
	end
	table.insert(w._refreshers, renderValue)
	build()
	if o.Default ~= nil then obj:Set(o.Default, true) end
	if o.Flag then w.Flags[o.Flag] = obj.Value; w.Setters[o.Flag] = function(v) obj:Set(v) end end
	obj.Frame = row
	return obj
end

function Tab:CreateColorPicker(o)
	local w = self.Window
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	row.ClipsDescendants = true
	local baseH = w.RowH
	label(self, row, o.Name, 0.7, o.Icon)
	local preview = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, (baseH - 20) / 2), Size = UDim2.fromOffset(34, 20), BorderSizePixel = 0, Parent = row })
	corner(preview, 6); w:_stroke(preview)
	local head = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, baseH), ZIndex = 2, Parent = row })
	local panel = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, baseH + 2), Size = UDim2.new(1, -24, 0, 150), Parent = row })

	local sv = new("Frame", { Size = UDim2.new(1, -30, 0, 100), BorderSizePixel = 0, Parent = panel })
	corner(sv, 6)
	local white = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = sv })
	corner(white, 6)
	new("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
	local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sv })
	corner(black, 6)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
	local svKnob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = sv })
	corner(svKnob, 6); new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = svKnob })

	local hueBar = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 20, 0, 100), BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1), Parent = panel })
	corner(hueBar, 6)
	local seq = {}
	for i = 0, 6 do table.insert(seq, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))) end
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(seq), Parent = hueBar })
	local hueKnob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 4, 0, 4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = hueBar })
	corner(hueKnob, 2)

	local alphaBar = new("Frame", { Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 0, 12), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = panel })
	corner(alphaBar, 6)
	local aGrad = new("UIGradient", { Transparency = NumberSequence.new(1, 0), Parent = alphaBar })
	w:_bind(alphaBar, "BackgroundColor3", "SubText")
	local aKnob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0, 4, 1, 4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = alphaBar })
	corner(aKnob, 2); new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = aKnob })

	local hex = new("TextBox", { Text = "", Font = Enum.Font.Code, TextSize = 12, ClearTextOnFocus = false, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 126),
		Size = UDim2.fromOffset(90, 22), Parent = panel })
	w:_bind(hex, "BackgroundColor3", "Background"); w:_bind(hex, "TextColor3", "Text"); corner(hex, 6)

	local def = o.Default or Color3.fromRGB(108, 99, 255)
	local obj: any = { Open = false, Alpha = o.Alpha or 1 }
	local h, s, v = def:ToHSV()
	local function commit(silent)
		local c = Color3.fromHSV(h, s, v)
		obj.Value = c
		preview.BackgroundColor3 = c
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svKnob.Position = UDim2.fromScale(s, 1 - v)
		hueKnob.Position = UDim2.fromScale(0.5, h)
		aKnob.Position = UDim2.fromScale(obj.Alpha, 0.5)
		aGrad.Transparency = NumberSequence.new(1, 0)
		alphaBar.BackgroundColor3 = c
		if not hex:IsFocused() then hex.Text = "#" .. c:ToHex() end
		preview.BackgroundTransparency = 1 - obj.Alpha
		w:_flag(o.Flag, { Color = c:ToHex(), Alpha = obj.Alpha })
		if not silent then call(o.Callback, c, obj.Alpha) end
	end
	function obj:Set(c, a, silent)
		if type(c) == "table" then c, a = Color3.fromHex(c.Color), c.Alpha end
		h, s, v = c:ToHSV()
		obj.Alpha = a or obj.Alpha
		commit(silent)
	end
	function obj:Get() return obj.Value, obj.Alpha end
	bindDrag(w.Maid, sv, function(rx, ry) s, v = rx, 1 - ry; commit() end)
	bindDrag(w.Maid, hueBar, function(_, ry) h = math.min(ry, 0.999); commit() end)
	bindDrag(w.Maid, alphaBar, function(rx) obj.Alpha = rx; commit() end)
	hex.FocusLost:Connect(function()
		local ok, c = pcall(Color3.fromHex, hex.Text)
		if ok and c then h, s, v = c:ToHSV() end
		commit()
	end)
	head.Activated:Connect(function()
		obj.Open = not obj.Open
		tw(row, { Size = UDim2.new(1, 0, 0, obj.Open and (baseH + 160) or baseH) }, 0.3)
	end)
	commit(true)
	if o.Flag then w.Setters[o.Flag] = function(val) obj:Set(val) end end
	obj.Frame = row
	return obj
end

-- Console / logger interno
function Tab:CreateConsole(o)
	o = o or {}
	local w = self.Window
	local row = self:_row(o.Name or "Console", (o.Height or 150) + 8, nil, nil)
	local scroll = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = row })
	new("UIListLayout", { Parent = scroll }); padding(scroll, 6, 4, 6, 4)
	local colors = { info = "SubText", success = "Success", warning = "Warning", error = "Error" }
	local obj: any = { Frame = row, Count = 0 }
	function obj:Log(text, kind)
		self.Count += 1
		local line = new("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = self.Count,
			Text = os.date("[%H:%M:%S] ") .. tostring(text), Parent = scroll })
		w:_bind(line, "TextColor3", colors[kind or "info"] or "SubText")
		local kids = scroll:GetChildren()
		if #kids > 150 then for _, k in ipairs(kids) do if k:IsA("TextLabel") then k:Destroy() break end end end
		task.defer(function() scroll.CanvasPosition = Vector2.new(0, 1e6) end)
	end
	function obj:Clear() for _, k in ipairs(scroll:GetChildren()) do if k:IsA("TextLabel") then k:Destroy() end end end
	table.insert(w.Consoles, obj)
	return obj
end

----------------------------------------------------------------------
-- 5. EXTRAS DA JANELA (v1.1)
----------------------------------------------------------------------

-- Snap/clamp nas bordas da tela ao soltar a janela
function Window:_snap()
	if not self.Snap then return end
	local a, sz, vp = self.Root.AbsolutePosition, self.Root.AbsoluteSize, self.Gui.AbsoluteSize
	local m, d = 10, 24
	local function axis(lo, size, total)
		if size + 2 * m > total then return 0 end
		local hi = total - (lo + size)
		if lo < d then return m - lo end
		if hi < d then return hi - m end
		return 0
	end
	local dx, dy = axis(a.X, sz.X, vp.X), axis(a.Y, sz.Y, vp.Y)
	if dx ~= 0 or dy ~= 0 then
		local p = self.Root.Position
		tw(self.Root, { Position = UDim2.new(p.X.Scale, p.X.Offset + dx, p.Y.Scale, p.Y.Offset + dy) }, 0.25, EASE.Back)
	end
end

--[[ Partículas animadas no fundo. cfg = { Style="Float|Rise|Snow|Stars", Count=22, Speed=1, Size=4 } ou false p/ desligar
     Só usa tweens encadeados (sem loop por frame) e pausa quando a janela está oculta/minimizada. ]]
function Window:SetParticles(cfg)
	self._pToken = (self._pToken or 0) + 1
	if self.ParticleLayer then self.ParticleLayer:Destroy(); self.ParticleLayer = nil end
	if not cfg then return end
	if cfg == true then cfg = {} end
	if type(cfg) == "string" then cfg = { Style = cfg } end
	local token = self._pToken
	local style, count, speed, psize = cfg.Style or "Float", cfg.Count or 22, cfg.Speed or 1, cfg.Size or 4
	local rng = Random.new()
	local layer = new("Frame", { Name = "Particles", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0, ClipsDescendants = true, Parent = self.Main })
	self.ParticleLayer = layer

	local function cycle(p, first)
		if self._pToken ~= token or not p.Parent then return end
		if not self.Visible or self.Minimized then
			task.delay(1, function() cycle(p, first) end)
			return
		end
		local dur, goal, ease = rng:NextNumber(7, 14) / speed, nil, EASE.Sine
		if style == "Rise" or style == "Snow" then
			local y0 = first and rng:NextNumber(-0.05, 1.05) or (style == "Rise" and 1.05 or -0.05)
			local y1 = style == "Rise" and -0.05 or 1.05
			local x0 = first and p.Position.X.Scale or rng:NextNumber()
			p.Position = UDim2.fromScale(x0, y0)
			dur = dur * math.abs(y1 - y0) / 1.1
			goal = { Position = UDim2.fromScale(math.clamp(x0 + rng:NextNumber(-0.12, 0.12), 0, 1), y1) }
			ease = EASE.Linear
		elseif style == "Stars" then
			dur = rng:NextNumber(1, 3) / speed
			goal = { BackgroundTransparency = rng:NextNumber(0.3, 0.95) }
		else
			goal = { Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), BackgroundTransparency = rng:NextNumber(0.6, 0.9) }
		end
		tw(p, goal, math.max(dur, 0.3), ease, DIR.InOut).Completed:Connect(function() cycle(p, false) end)
	end

	for i = 1, count do
		local s = psize * rng:NextNumber(0.5, 1.5)
		local p = new("Frame", { Size = UDim2.fromOffset(s, s), AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
			Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), BackgroundTransparency = rng:NextNumber(0.6, 0.9), Parent = layer })
		corner(p, 100)
		self:_bind(p, "BackgroundColor3", i % 2 == 0 and "Accent" or "Accent2")
		task.delay(rng:NextNumber(0, 2), function() cycle(p, true) end)
	end
end

-- Gradiente animado suave sobre o fundo
function Window:SetBackgroundFx(on)
	if self.BgFx then self.BgFx:Destroy(); self.BgFx = nil end
	if not on then return end
	local f = new("Frame", { Name = "BgFx", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 0, Parent = self.Main })
	local g = new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(1, 0.97) }), Parent = f })
	local function paint() g.Color = ColorSequence.new(self.Theme.Accent, self.Theme.Accent2) end
	paint()
	table.insert(self._refreshers, paint)
	TweenService:Create(g, TweenInfo.new(14, EASE.Linear, DIR.Out, -1), { Rotation = 360 }):Play()
	self.BgFx = f
end

-- HUD arrastável com FPS e ping
function Window:CreateHud(o)
	o = o or {}
	local f = new("Frame", { AutomaticSize = Enum.AutomaticSize.XY, Position = UDim2.fromOffset(12, 12), BorderSizePixel = 0, ZIndex = 40, Parent = self.Gui })
	self:_bind(f, "BackgroundColor3", "Surface"); corner(f, 8); self:_stroke(f)
	local l = new("TextLabel", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Font = Enum.Font.GothamMedium, TextSize = 12, Text = "", Parent = f })
	self:_bind(l, "TextColor3", "Text"); padding(l, 10, 6, 10, 6)
	makeDraggable(self.Maid, f, f)
	local obj: any, fps, acc, frames = { Extra = "" }, 60, 0, 0
	local function render()
		local ping = 0
		pcall(function() ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) end)
		l.Text = (o.Text or self.TitleLabel.Text) .. "  •  " .. fps .. " FPS  •  " .. ping .. " ms" .. (obj.Extra ~= "" and ("  •  " .. obj.Extra) or "")
	end
	local conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt; frames += 1
		if acc >= 0.5 then fps = math.floor(frames / acc + 0.5); acc, frames = 0, 0; render() end
	end)
	self.Maid:Add(conn)
	render()
	function obj:SetText(t) obj.Extra = t; render() end
	function obj:SetVisible(v) f.Visible = v end
	function obj:Destroy() conn:Disconnect(); f:Destroy() end
	obj.Frame = f
	return obj
end

-- Configuração: JSON, arquivo (executores) e auto-save
function Window:ExportConfig() return HttpService:JSONEncode(self.Flags) end
function Window:ImportConfig(str)
	local ok, t = pcall(function() return HttpService:JSONDecode(str) end)
	if ok and type(t) == "table" then self:LoadConfig(t) return true end
	return false
end
function Window:SaveToFile(name)
	if not writefile then return false end
	return (pcall(writefile, name .. ".json", self:ExportConfig()))
end
function Window:LoadFromFile(name)
	if not (isfile and readfile) then return false end
	local ok, data = pcall(function()
		if isfile(name .. ".json") then return readfile(name .. ".json") end
		return nil
	end)
	return ok and data ~= nil and self:ImportConfig(data)
end
function Window:AutoSave(name)
	local token = 0
	self.FlagChanged:Connect(function()
		token += 1
		local my = token
		task.delay(1, function() if my == token and not self._destroyed then self:SaveToFile(name) end end)
	end)
end

----------------------------------------------------------------------
-- 6. SUB-ABAS, GRUPOS E NOVOS COMPONENTES (v1.1)
----------------------------------------------------------------------

function Tab:_addSubEntry(name, scroll)
	local w = self.Window
	local btn = new("TextButton", { Text = name, Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false, BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 28), BorderSizePixel = 0, LayoutOrder = #self.SubEntries + 1, Parent = self.SubBar })
	corner(btn, 8); padding(btn, 12, 0, 12, 0)
	local ul = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, 0, 0, 2), BorderSizePixel = 0, Parent = btn })
	corner(ul, 1); w:_bind(ul, "BackgroundColor3", "Accent")
	local entry: any = { Name = name, Scroll = scroll, Button = btn }
	entry.render = function(instant)
		local on = self.ActiveSub == entry
		local t = instant and 0 or 0.2
		tw(btn, { TextColor3 = on and w.Theme.Text or w.Theme.SubText }, t)
		tw(ul, { Size = UDim2.new(on and 1 or 0, on and -16 or 0, 0, 2) }, t, EASE.Back)
	end
	entry.select = function()
		if self.ActiveSub == entry then return end
		local prev = self.ActiveSub
		self.ActiveSub = entry
		if prev then prev.Scroll.Visible = false; prev.render() end
		scroll.Visible = true
		scroll.Position = UDim2.fromOffset(0, 54)
		tw(scroll, { Position = UDim2.fromOffset(0, 38) }, 0.3)
		entry.render()
		w:_applySearch()
	end
	btn.Activated:Connect(function() w:_sound("click"); entry.select() end)
	table.insert(w._refreshers, entry.render)
	table.insert(self.SubEntries, entry)
	entry.render(true)
	if not self.ActiveSub then entry.select() end
	return entry
end

--[[ Sub-aba: devolve um objeto com TODOS os métodos de componente (CreateButton etc).
     Crie as sub-abas ANTES de adicionar componentes direto na aba; o que já existir
     na aba vira a sub-aba "Geral". ]]
function Tab:CreateSubTab(name)
	local w = self.Window
	self.Subs = self.Subs or {}
	if not self.SubBar then
		local bar = new("ScrollingFrame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.X, Parent = self.Page })
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center, Parent = bar })
		padding(bar, 10, 2, 10, 2)
		self.SubBar, self.SubEntries = bar, {}
		self.Scroll.Position, self.Scroll.Size = UDim2.fromOffset(0, 38), UDim2.new(1, 0, 1, -38)
		if #self.Elements > 0 then self:_addSubEntry("Geral", self.Scroll) else self.Scroll.Visible = false end
	end
	local sc = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -38), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false, Parent = self.Page })
	w:_bind(sc, "ScrollBarImageColor3", "Accent")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sc })
	padding(sc, 10, 2, 12, 10)
	local sub: any = setmetatable({ Window = w, Name = name, Elements = {}, Subs = {}, Scroll = sc, Parent = self, IsSub = true }, Tab)
	table.insert(self.Subs, sub)
	local entry = self:_addSubEntry(name, sc)
	function sub:Select() entry.select() end
	w:_action("Ir para: " .. self.Name .. " › " .. name, function() w:SelectTab(self); entry.select() end)
	return sub
end

-- Grupo recolhível: também devolve um objeto com todos os componentes
function Tab:CreateGroup(o)
	local w = self.Window
	self.Subs = self.Subs or {}
	local frame = new("Frame", { Name = o.Name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
		LayoutOrder = #self.Elements + 1, Parent = self.Scroll })
	w:_bind(frame, "BackgroundColor3", "Surface"); corner(frame, 10); w:_stroke(frame)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
	local head = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, w.RowH), LayoutOrder = 1, Parent = frame })
	local t = w:_text(head, o.Name, "Text", 14, Enum.Font.GothamBold)
	t.Position, t.Size = UDim2.fromOffset(12, 0), UDim2.new(1, -40, 1, 0)
	local arrow = w:_icon(head, "chevron-down", 16, "SubText").Frame
	arrow.AnchorPoint, arrow.Position = Vector2.new(1, 0.5), UDim2.new(1, -12, 0.5, 0)
	if o.Icon then
		local gi = w:_icon(head, o.Icon, 16, "Accent")
		gi.Frame.Position = UDim2.new(0, 12, 0.5, -8)
		t.Position, t.Size = UDim2.fromOffset(36, 0), UDim2.new(1, -64, 1, 0)
	end
	local content = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = frame })
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	padding(content, 8, 2, 8, 10)
	local g: any = setmetatable({ Window = w, Name = o.Name, Elements = {}, Subs = {}, Scroll = content, Parent = self, IsGroup = true, Frame = frame }, Tab)
	table.insert(self.Elements, { Frame = frame, Name = o.Name, Always = true })
	table.insert(self.Subs, g)
	local open = o.Open ~= false
	function g:SetOpen(v) open = v; content.Visible = v; tw(arrow, { Rotation = v and 0 or -90 }, 0.2) end
	head.Activated:Connect(function() g:SetOpen(not open) end)
	g:SetOpen(open)
	return g
end

-- Vários botões lado a lado
function Tab:CreateButtonRow(o)
	local w = self.Window
	local n = #o.Buttons
	local names = {}
	for _, b in ipairs(o.Buttons) do table.insert(names, b.Text) end
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, w.RowH), BackgroundTransparency = 1, LayoutOrder = #self.Elements + 1, Parent = self.Scroll })
	table.insert(self.Elements, { Frame = f, Name = table.concat(names, " ") })
	for i, b in ipairs(o.Buttons) do
		local danger = b.Style == "Danger"
		local bt = new("TextButton", { Text = b.Text, Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false, BorderSizePixel = 0,
			Position = UDim2.new((i - 1) / n, 3, 0, 0), Size = UDim2.new(1 / n, -6, 1, 0), Parent = f })
		corner(bt, 8); w:_stroke(bt)
		w:_bind(bt, "BackgroundColor3", danger and "Error" or "Element")
		w:_bind(bt, "TextColor3", danger and "OnAccent" or "Text")
		bt.MouseEnter:Connect(function() if not danger then tw(bt, { BackgroundColor3 = w.Theme.ElementHover }, 0.15) end end)
		bt.MouseLeave:Connect(function() if not danger then tw(bt, { BackgroundColor3 = w.Theme.Element }, 0.15) end end)
		bt.Activated:Connect(function() w:_sound("click"); call(b.Callback) end)
		w:_action("Executar: " .. b.Text, function() call(b.Callback) end)
	end
	return { Frame = f }
end

-- Valor numérico com [-] [+]
function Tab:CreateStepper(o)
	local w = self.Window
	local min, max, step = o.Min or 0, o.Max or 100, o.Step or 1
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	label(self, row, o.Name, 0.5, o.Icon)
	local sz = w.RowH - 10
	local function sbtn(txt, x)
		local b = new("TextButton", { Text = txt, Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(sz, sz), Parent = row })
		w:_bind(b, "BackgroundColor3", "Background"); w:_bind(b, "TextColor3", "Accent"); corner(b, 6)
		return b
	end
	local plus, minus = sbtn("+", -8), sbtn("–", -8 - sz - 56)
	local val = w:_text(row, "", "Text", 14, Enum.Font.GothamBold)
	val.AnchorPoint, val.Position, val.Size, val.TextXAlignment = Vector2.new(1, 0.5), UDim2.new(1, -8 - sz - 4, 0.5, 0), UDim2.fromOffset(48, sz), Enum.TextXAlignment.Center
	local obj: any = { Value = o.Default or min }
	function obj:Set(v, silent)
		self.Value = math.clamp(v, min, max)
		val.Text = tostring(self.Value)
		w:_flag(o.Flag, self.Value)
		if not silent then call(o.Callback, self.Value) end
	end
	function obj:Get() return self.Value end
	plus.Activated:Connect(function() obj:Set(obj.Value + step) end)
	minus.Activated:Connect(function() obj:Set(obj.Value - step) end)
	obj:Set(obj.Value, true)
	if o.Flag then w.Flags[o.Flag] = obj.Value; w.Setters[o.Flag] = function(v) obj:Set(v) end end
	obj.Frame = row
	return obj
end

-- Valor em destaque (ex.: Ping, Kills, Status)
function Tab:CreateStat(o)
	local w = self.Window
	local row = self:_row(o.Name, nil, o.Tooltip, o.Menu)
	label(self, row, o.Name, 0.5, o.Icon)
	local v = w:_text(row, tostring(o.Value or "-"), "Accent", 15, Enum.Font.GothamBold)
	v.AnchorPoint, v.Position, v.Size, v.TextXAlignment = Vector2.new(1, 0.5), UDim2.new(1, -12, 0.5, 0), UDim2.new(0.5, -12, 1, 0), Enum.TextXAlignment.Right
	local obj: any = { Frame = row }
	function obj:Set(val, colorKey)
		v.Text = tostring(val)
		if colorKey and w.Theme[colorKey] then tw(v, { TextColor3 = w.Theme[colorKey] }, 0.2) end
	end
	return obj
end

-- Gráfico de barras ao vivo: :Push(valor)
function Tab:CreateGraph(o)
	local w = self.Window
	local H, n = o.Height or 96, o.Points or 30
	local row = self:_row(o.Name, H, o.Tooltip, o.Menu)
	local t = w:_text(row, o.Name)
	t.Position, t.Size = UDim2.fromOffset(12, 6), UDim2.new(0.6, -12, 0, 18)
	local cur = w:_text(row, "0", "Accent", 13, Enum.Font.GothamBold)
	cur.AnchorPoint, cur.Position, cur.Size, cur.TextXAlignment = Vector2.new(1, 0), UDim2.new(1, -12, 0, 6), UDim2.new(0.4, -12, 0, 18), Enum.TextXAlignment.Right
	local area = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 1, -38), Parent = row })
	local bars, vals = {}, {}
	for i = 1, n do
		vals[i] = 0
		bars[i] = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new((i - 1) / n, 1, 1, 0), Size = UDim2.new(1 / n, -2, 0, 2), BorderSizePixel = 0, Parent = area })
		corner(bars[i], 2); w:_bind(bars[i], "BackgroundColor3", "Accent")
	end
	local obj: any = { Frame = row }
	local function render()
		local mx = o.Max or 0
		if not o.Max then for _, x in ipairs(vals) do if x > mx then mx = x end end end
		if mx <= 0 then mx = 1 end
		for i = 1, n do tw(bars[i], { Size = UDim2.new(1 / n, -2, math.clamp(vals[i] / mx, 0, 1), 2) }, 0.15) end
	end
	function obj:Push(v)
		table.remove(vals, 1)
		table.insert(vals, v)
		cur.Text = string.format("%.1f", v) .. (o.Suffix or "")
		render()
	end
	function obj:Clear() for i = 1, n do vals[i] = 0 end; cur.Text = "0"; render() end
	return obj
end

-- Galeria clicável com todos os ícones registrados (útil para escolher o nome)
function Tab:CreateIconGallery(o)
	o = o or {}
	local w = self.Window
	local row = self:_row(o.Name or "Galeria de ícones", 10, nil, nil, true)
	row.AutomaticSize, row.Size = Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 0)
	padding(row, 8, 8, 8, 8)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(74, 66), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	for i, name in ipairs(Aurora.IconNames()) do
		local cell = new("TextButton", { Text = "", AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i, Parent = row })
		w:_bind(cell, "BackgroundColor3", "Background"); corner(cell, 8)
		local ic = w:_icon(cell, name, 26, "Text")
		ic.Frame.AnchorPoint, ic.Frame.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 10)
		local l = w:_text(cell, name, "SubText", 10, Enum.Font.Gotham)
		l.Position, l.Size, l.TextXAlignment = UDim2.new(0, 2, 1, -18), UDim2.new(1, -4, 0, 14), Enum.TextXAlignment.Center
		cell.MouseEnter:Connect(function() ic:SetColor(w.Theme.Accent, 0.15); tw(cell, { BackgroundColor3 = w.Theme.ElementHover }, 0.15) end)
		cell.MouseLeave:Connect(function() ic:SetColor(w.Theme.Text, 0.15); tw(cell, { BackgroundColor3 = w.Theme.Background }, 0.15) end)
		cell.Activated:Connect(function()
			if setclipboard then pcall(setclipboard, name) end
			call(o.Callback, name)
			w:Notify({ Title = "Ícone: " .. name, Content = 'Use  Icon = "' .. name .. '"', Type = "info", Duration = 2 })
		end)
	end
	return { Frame = row }
end

return Aurora
