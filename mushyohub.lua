-- MushYO Hub | Pesca, manutenção e previsão de sinuca | RetroBox API 2 (stable)
local created

local function installSnooker(window, Library, player, RS, proto, ups)
    local physics = require(RS.Modules.SnookerPhysics)
    local config = require(RS.Configuration.Snooker)
    local client = require(RS.Client.Snooker)
    local diameter = RS.Assets.Snooker.Ball:GetExtentsSize().X
    assert(type(client.Cue) == "function" and type(physics.Step) == "function", "Física da sinuca indisponível.")
    local pool = {message = "Previsão desligada", scanAt = 0, lines = {}, markers = {}, shown = {}, generation = 0}
    local scope = window:CreateScope()
    local folder = Instance.new("Folder")
    folder.Name = "MushyoHub_SnookerPreview"
    folder.Parent = workspace
    scope:Add(folder)
    local forceState = window:CreateState(0)
    local contactState = window:CreateState("—")
    local timeState = window:CreateState(0)
    local collisionState = window:CreateState(0)
    local tab = window:CreateTab({Title = "Sinuca", Icon = "target", Columns = 1})
    local section = tab:CreateSection({Title = "Previsão da tacada", Icon = "target"})
    local toggle = section:AddToggle({Id = "mush.snooker.enabled", Title = "Mostrar previsão de sinuca",
        Icon = "eye", Default = false,
        Tooltip = "Lê a mira e a carga reais do taco. Simula cópias das bolas usando SnookerPhysics do jogo: colisões, tabelas, atrito e caçapas.",
        Floating = {Text = "SINUCA", MobileOnly = true, Position = Vector2.new(.04, .76)}})
    section:AddSlider({Id = "mush.snooker.power", Title = "Força de prévia", Icon = "sliders",
        Min = 4, Max = 100, Step = 1, Default = 50, Suffix = "%",
        Tooltip = "Usada antes de segurar o botão da tacada. Enquanto carrega, a previsão usa a força real do taco; este controle não muda a força aplicada pelo jogo."})
    local options = tab:CreateSection({Title = "Trajetórias e marcas", Icon = "eye", Collapsible = true})
    options:AddToggle({Id = "mush.snooker.white", Title = "Trajetória da bola branca", Default = true, Icon = "target",
        Tooltip = "Mostra o percurso completo previsto da branca, inclusive depois de bater em bolas e tabelas."})
    options:AddToggle({Id = "mush.snooker.others", Title = "Trajetórias das bolas atingidas", Default = true, Icon = "grid",
        Tooltip = "Inclui todas as bolas que se moverem na simulação, inclusive colisões em sequência."})
    options:AddToggle({Id = "mush.snooker.stops", Title = "Marcar posições finais e caçapas", Default = true, Icon = "notification",
        Tooltip = "Esferas transparentes marcam os pontos finais. A etiqueta identifica a bola e informa quando ela cairá numa caçapa."})
    options:AddToggle({Id = "mush.snooker.keep-shot", Title = "Manter previsão durante a tacada", Default = true, Icon = "eye",
        Tooltip = "Congela a última previsão enquanto as bolas reais se movem, para você comparar o resultado."})
    options:AddSlider({Id = "mush.snooker.refresh", Title = "Atualizações por segundo", Icon = "sliders",
        Min = 2, Max = 10, Step = 1, Default = 6, Suffix = " /s",
        Tooltip = "Limita a frequência das simulações. Reduza se o computador perder FPS; as execuções nunca se sobrepõem."})
    options:AddSlider({Id = "mush.snooker.width", Title = "Espessura das linhas", Icon = "sliders",
        Min = .01, Max = .09, Step = .005, Default = .03,
        Tooltip = "Espessura das linhas em studs; apenas visual."})
    local resultSection = tab:CreateSection({Title = "Resultado previsto", Icon = "grid"})
    local row = resultSection:CreateRow({Gap = 10, StackAt = 440})
    row:AddStatCard({Id = "mush.snooker.stat.power", Title = "Força simulada", Icon = "sliders",
        State = forceState, TwoWay = false, Format = "Percent", Precision = 1, Subtitle = "Prévia ou carga real do taco"})
    row:AddStatCard({Id = "mush.snooker.stat.contact", Title = "Primeira bola atingida", Icon = "target",
        State = contactState, TwoWay = false, Format = "Raw"})
    local row2 = resultSection:CreateRow({Gap = 10, StackAt = 440})
    row2:AddStatCard({Id = "mush.snooker.stat.time", Title = "Tempo até parar", Icon = "info",
        State = timeState, TwoWay = false, Format = "Raw", Precision = 2, Unit = "s"})
    row2:AddStatCard({Id = "mush.snooker.stat.collisions", Title = "Colisões e tabelas", Icon = "grid",
        State = collisionState, TwoWay = false, Format = "Raw"})
    local status = resultSection:AddLabel({Id = "mush.snooker.status", Title = "Estado", Icon = "info",
        Default = "Previsão desligada", Height = 75})
    local details = resultSection:AddLabel({Id = "mush.snooker.details", Title = "Caçapas e posições finais", Icon = "notification",
        Default = "Entre numa partida e ative a previsão.", Height = 85})
    local function numberText(value) return type(value) == "number" and string.format("%.2f", value) or "—" end
    local positions = resultSection:AddDataTable({Id = "mush.snooker.positions", Title = "Destino das bolas", Icon = "grid",
        Rows = {}, Height = 260, Persist = false, Columns = {
            {Key = "Ball", Title = "Bola", Width = 90}, {Key = "Outcome", Title = "Destino", Width = 100},
            {Key = "Distance", Title = "Percurso", Width = 100, Format = numberText},
            {Key = "X", Title = "X", Width = 100, Format = numberText},
            {Key = "Y", Title = "Y", Width = 90, Format = numberText},
            {Key = "Z", Title = "Z", Width = 100, Format = numberText},
        }})
    section:AddLabel({Id = "mush.snooker.help", Title = "Como usar", Icon = "info", Height = 130,
        Default = "Entre numa mesa e termine de posicionar a branca.\nNa sua vez, mire: a linha usa a força de prévia.\nSegure a tacada: a previsão acompanha a carga real.\nCiano = branca; outras cores = bolas atingidas. FIM = parada prevista.\nA previsão em partida ainda precisa do seu teste."})

    function pool:Clear()
        for _, object in ipairs(self.shown) do
            if object:IsA("BasePart") then object.Transparency = 1 else object.Enabled = false end
        end
        table.clear(self.shown)
    end
    scope:Add(function() pool:Clear(); pool.callback = nil; pool.result = nil end)
    local function snapshotNative()
        local fn = pool.callback
        if not fn and os.clock() >= pool.scanAt then
            pool.scanAt = os.clock() + .5
            -- Proto 23: atualização do taco, verificado nesta versão do MushYO.
            for _, candidate in ipairs(proto(client.Cue, 23, true)) do
                if type(candidate) == "function" then
                    local u = ups(candidate)
                    if typeof(u[3]) == "Instance" and u[3]:IsA("Model") and type(u[1]) == "table"
                        and typeof(u[28]) == "Instance" and u[28].Parent and typeof(u[34]) == "Vector3" then
                        fn = candidate; pool.callback = fn; break
                    end
                end
            end
        end
        if not fn then return nil, "Entre numa partida de sinuca" end
        local u = ups(fn)
        if typeof(u[28]) ~= "Instance" or not u[28].Parent or not u[3].Parent then
            pool.callback = nil; pool.scanAt = 0; return nil, "Aguardando uma mesa ativa"
        end
        local model = u[3]
        if model:GetAttribute("ShooterId") ~= player.UserId then return nil, "Aguardando sua vez" end
        if u[1].Placing then return nil, "Posicione e confirme a bola branca" end
        if u[2][model] or model:GetAttribute("SnookerBusy") then
            return {model = model, busy = true, power = u[14], heading = u[15], held = true}, "Tacada em movimento"
        end
        local held = u[8] == true
        local power = held and math.clamp((os.clock() - u[27]) / 1.1, 0, 1)
            or u[12] and u[14] or window:GetFlag("mush.snooker.power") / 100
        local heading = u[12] and u[15] or u[34]
        return {model = model, heading = heading, power = power, held = held or u[12] ~= nil}
    end
    local function append(track, position)
        local points = track.points
        local last = points[#points]
        if (position - last).Magnitude < diameter * .015 then return end
        if #points >= 2 then
            local previous = points[#points - 1]
            local a, b = last - previous, position - last
            if a.Magnitude > 0 and b.Magnitude > 0 and a.Unit:Dot(b.Unit) > .9997 then
                points[#points] = position
                return
            end
        end
        if #points < 160 then points[#points + 1] = position else track.limited = true; points[#points] = position end
    end
    local function predict(ctx, aim, baseline)
        local frame = physics.BuildFrame(aim.model, diameter)
        assert(frame, "Geometria da mesa ainda não carregada.")
        local state = physics.NewState(frame)
        local tracks = {}
        if baseline then
            -- Ao soltar o taco, refaz com a força exata usando as posições anteriores à tacada.
            for id, track in pairs(baseline.tracks) do
                physics.AddBall(state, id, track.initial)
                tracks[id] = {id = id, points = {track.initial}, initial = track.initial, distance = 0}
            end
        else
            local balls = aim.model:FindFirstChild("Balls")
            assert(balls, "Bolas da mesa ainda não carregadas.")
            for _, model in ipairs(balls:GetChildren()) do
                local id = model:GetAttribute("BallId")
                local root = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart"))
                if type(id) == "number" and root then
                    local pos = physics.WorldToLocal(frame, root.Position)
                    local ball = physics.AddBall(state, id, pos)
                    ball.Pocketed = model:GetAttribute("Pocketed") == true
                    if not ball.Pocketed then tracks[id] = {id = id, points = {pos}, initial = pos, distance = 0} end
                end
            end
        end
        assert(tracks[0], "Bola branca indisponível.")
        ctx:ThrowIfCancelled()
        physics.ApplyStrike(state, aim.power, aim.heading)
        local result = {frame = frame, tracks = tracks, model = aim.model, power = aim.power,
            realPower = aim.held, collisions = 0, time = 0, pocketed = {}, moved = 0}
        local dt, slice = config.GetFixedDt(), os.clock()
        local limit = math.ceil(config.GetMaxSimTime() / dt)
        for step = 1, limit do
            ctx:ThrowIfCancelled()
            if physics.Settled(state) then break end
            local ev = physics.Step(state)
            result.time = step * dt
            result.collisions += ev.Collisions
            for _, id in ipairs(ev.Pocketed) do result.pocketed[id] = true end
            local white = physics.GetBall(state, 0)
            if not result.first and ev.Collisions > 0 then
                local nearest = math.huge
                for _, ball in ipairs(state.Balls) do
                    if ball.Id ~= 0 and not ball.Pocketed and ball.Vel.Magnitude > config.GetRestSpeed() then
                        local distance = (ball.Pos - white.Pos).Magnitude
                        if distance < nearest then nearest = distance; result.first = ball.Id; result.contact = white.Pos end
                    end
                end
            end
            local settled = physics.Settled(state)
            if step % 6 == 0 or ev.Collisions > 0 or #ev.Pocketed > 0 or settled then
                for id, track in pairs(tracks) do
                    local ball = physics.GetBall(state, id)
                    if ball and (ball.Pos - track.initial).Magnitude > diameter * .015 then append(track, ball.Pos) end
                end
            end
            if step % 24 == 0 and os.clock() - slice > .003 then
                task.wait()
                ctx:ThrowIfCancelled()
                slice = os.clock()
            end
            if settled then break end
        end
        result.settled = physics.Settled(state)
        for id, track in pairs(tracks) do
            local ball = physics.GetBall(state, id)
            append(track, ball.Pos)
            track.final, track.pocketed = ball.Pos, ball.Pocketed
            track.moved = #track.points > 1
            if track.moved then result.moved += 1 end
            for i = 2, #track.points do track.distance += (track.points[i] - track.points[i - 1]).Magnitude end
        end
        return result
    end
    local function makePart(name)
        local part = Instance.new("Part")
        part.Name = name; part.Anchored = true; part.CanCollide = false
        part.CanTouch = false; part.CanQuery = false; part.CastShadow = false
        part.Material = Enum.Material.Neon; part.Transparency = 1; part.Parent = folder
        return part
    end
    local function ballColor(id)
        if id == 0 then return Color3.fromRGB(65, 240, 255) end
        if id == 8 then return Color3.fromRGB(245, 90, 210) end
        local color = config.GetColor(id) or Color3.fromRGB(170, 255, 90)
        return color:Lerp(Color3.new(1, 1, 1), .25)
    end
    local function show(object)
        pool.shown[#pool.shown + 1] = object
    end
    local function line(index, a, b, color, width)
        local length = (b - a).Magnitude
        if length < .002 then return end
        local part = pool.lines[index]
        if not part then part = makePart("Trajectory"); pool.lines[index] = part end
        part.Size = Vector3.new(width, width, length)
        part.CFrame = CFrame.lookAt((a + b) * .5, b)
        part.Color = color; part.Transparency = .12
        show(part)
    end
    local function marker(id, position, color, text)
        local object = pool.markers[id]
        if not object then
            local part = makePart("Stop_" .. id)
            part.Shape = Enum.PartType.Ball
            local gui = Instance.new("BillboardGui")
            gui.Size = UDim2.fromOffset(110, 30); gui.AlwaysOnTop = true
            gui.StudsOffsetWorldSpace = Vector3.new(0, diameter * 1.4, 0)
            gui.Adornee = part; gui.Enabled = false; gui.Parent = part
            local label = Instance.new("TextLabel")
            label.Size = UDim2.fromScale(1, 1); label.BackgroundTransparency = 1
            label.TextColor3 = Color3.new(1, 1, 1); label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.TextStrokeTransparency = .1; label.TextSize = 13; label.Font = Enum.Font.Code; label.Parent = gui
            object = {part = part, gui = gui, label = label}; pool.markers[id] = object
        end
        object.part.Size = Vector3.one * diameter * .95
        object.part.CFrame = CFrame.new(position); object.part.Color = color; object.part.Transparency = .65
        object.label.Text = text; object.gui.Enabled = true
        show(object.part); show(object.gui)
    end
    local function draw(result)
        pool:Clear()
        local index, rows, potted = 0, {}, {}
        local width = window:GetFlag("mush.snooker.width")
        for id = 0, 15 do
            local track = result.tracks[id]
            local visible = id == 0 and window:GetFlag("mush.snooker.white") or id ~= 0 and window:GetFlag("mush.snooker.others")
            if track and track.moved then
                local name = id == 0 and "Branca" or tostring(id)
                if track.pocketed then potted[#potted + 1] = name end
                if visible then
                    local color = ballColor(id)
                    for i = 2, #track.points do
                        if index >= 512 then break end
                        index += 1
                        local a = physics.LocalToWorld(result.frame, track.points[i - 1])
                        local b = physics.LocalToWorld(result.frame, track.points[i])
                        line(index, a, b, color, width)
                    end
                    if window:GetFlag("mush.snooker.stops") then
                        marker(id, physics.LocalToWorld(result.frame, track.final), color,
                            name .. (track.pocketed and " · CAÇAPA" or " · FIM"))
                    end
                end
                local world = physics.LocalToWorld(result.frame, track.final)
                rows[#rows + 1] = {Id = tostring(id), Ball = name, Outcome = track.pocketed and "Caçapa" or "Parada",
                    Distance = track.distance, X = world.X, Y = world.Y, Z = world.Z}
            end
        end
        local warning = result.pocketed[0] and "Atenção: a branca cairá na caçapa.\n" or ""
        details:SetText(warning .. "Caçapas: " .. (#potted > 0 and table.concat(potted, ", ") or "nenhuma")
            .. "\nA tabela abaixo mostra as posições finais em studs.")
        positions:SetRows(rows)
        Library:Batch(function()
            forceState:Set(result.power * 100); timeState:Set(result.time)
            contactState:Set(result.first and tostring(result.first) or "Nenhuma")
            collisionState:Set(result.collisions)
        end)
    end
    local job = window:CreateTask({Id = "mush.snooker.preview", Interval = 1 / 6, Start = false, OnError = "Continue",
        Callback = function(ctx)
            ctx:ThrowIfCancelled()
            local aim, reason = snapshotNative()
            if not aim then pool:Clear(); pool.message = reason; status:SetText(reason); return end
            if aim.busy then
                if not window:GetFlag("mush.snooker.keep-shot") or not pool.result or pool.result.model ~= aim.model then
                    pool:Clear()
                elseif not pool.result.lockedShot and type(aim.power) == "number" and aim.power >= .04 then
                    local result = predict(ctx, aim, pool.result)
                    ctx:ThrowIfCancelled()
                    result.lockedShot = true
                    pool.result = result
                    draw(result)
                end
                pool.message = reason; status:SetText(reason .. " · previsão congelada"); return
            end
            if aim.power < .04 then pool:Clear(); status:SetText("Carregue pelo menos 4% para uma tacada válida"); return end
            local result = predict(ctx, aim)
            ctx:ThrowIfCancelled()
            local current = snapshotNative()
            if not current or current.model ~= aim.model then pool:Clear(); return end
            if current.busy and type(current.power) == "number" and current.power >= .04 then
                result = predict(ctx, current, result)
                ctx:ThrowIfCancelled()
                result.lockedShot = true
            end
            pool.result = result
            draw(result)
            pool.message = string.format("%s · %.1f%% · %d bolas movidas%s", aim.held and "Carga real" or "Força de prévia",
                aim.power * 100, result.moved, result.settled and "" or " · limite de tempo atingido")
            status:SetText(pool.message)
            return {Power = result.power, FirstBall = result.first, Seconds = result.time, Moved = result.moved}
        end})
    pool.job = job
    toggle:BindTask(job)
    scope:Add(window:GetFlagState("mush.snooker.enabled"):Subscribe(function(enabled)
        if not enabled then pool:Clear(); pool.message = "Previsão desligada"; status:SetText(pool.message) end
    end, true), "Disconnect")
    scope:Add(window:GetFlagState("mush.snooker.refresh"):Subscribe(function(value) job:SetInterval(1 / value) end, true), "Disconnect")
    for _, id in ipairs({"mush.snooker.white", "mush.snooker.others", "mush.snooker.stops", "mush.snooker.width"}) do
        scope:Add(window:GetFlagState(id):Subscribe(function() if pool.result and job:GetStatus().Requested then draw(pool.result) end end), "Disconnect")
    end
    scope:Add(window:OnError(function(entry)
        if entry.ControlId == "mush.snooker.preview" then pool:Clear(); status:SetText("Sinuca: " .. tostring(entry.Message)) end
    end), "Disconnect")
    function pool:GetSnapshot()
        local r = self.result
        return {enabled = job:GetStatus().Requested, status = self.message, power = r and r.power,
            firstBall = r and r.first, seconds = r and r.time, moved = r and r.moved, collisions = r and r.collisions}
    end
    return pool
end

-- Backend compartilhado pelas tarefas de pesca e manutenção.
local function createMaintenance(player, RS, RF, events, config, ups, manage)
    require(RS.Configuration.Dialogs.Fisherman)
    local handlers = ups(events.Bind)[1]
    local inventory = ups(require(RF.Interface.Build.FishInventory).CreateWindow)
    local m = {sales = 0, sold = 0, repairs = 0, earned = 0, spent = 0,
        status = "Pronto", nextAttempt = 0, revision = 0}
    local rodsGetter, equippedObserver, silverGetter, fishLocks, laganLocks
    for _, fn in pairs(handlers.FishingRodsChanged or {}) do
        if debug.info(fn, "s"):find("Dialogs.Fisherman", 1, true) then rodsGetter = ups(fn)[2]; break end
    end
    for _, fn in pairs(handlers.EquippedRodChanged or {}) do
        if debug.info(fn, "s"):find("Tools.Fish", 1, true) then equippedObserver = fn; break end
    end
    local function getterFor(name, expected)
        for _, fn in pairs(handlers[name] or {}) do
            local ok, value = pcall(fn)
            if ok and type(value) == expected then return fn end
        end
    end
    silverGetter = getterFor("SilverCreditsChanged", "number")
    fishLocks = getterFor("LockedFishesUpdated", "table")
    laganLocks = getterFor("LockedLaganUpdated", "table")
    assert(type(rodsGetter) == "function" and silverGetter and equippedObserver,
        "Dados nativos de venda/reparação ainda indisponíveis.")
    for _, index in ipairs({11, 12, 13}) do
        assert(type(inventory[index]) == "function", "A estrutura do inventário mudou.")
    end
    manage(events:Bind("FishingRodsChanged", function() m.revision += 1 end), "Disconnect")

    function m:Read()
        local fishes, ores, lagan = inventory[11](), inventory[12](), inventory[13]()
        local lockedFish, lockedLagan = fishLocks and fishLocks() or {}, laganLocks and laganLocks() or {}
        local sellable = 0
        for _, item in pairs(fishes) do if not lockedFish[item.Index] then sellable += 1 end end
        for index, item in pairs(lagan) do if not lockedLagan[item.Index or index] then sellable += 1 end end
        local equipped = ups(equippedObserver)[1]
        local rod
        for index, item in pairs(rodsGetter()) do
            if item.Name == equipped then
                local info = config.fishingRods[item.Name]
                if info then rod = {Index = index, Name = item.Name, Current = item.Durability or 0,
                    Max = info.Durability, Price = info.Price, Repairable = info.CanPurchase ~= false} end
                break
            end
        end
        return {count = #fishes + #ores + #lagan, fishCount = #fishes, laganCount = #lagan,
            capacity = config.MAX_FISHES + (player:GetAttribute("extraFishCapacity") == true and 35 or 0),
            sellable = sellable, silver = silverGetter(), rod = rod}
    end
    local function waitFor(ctx, test, seconds)
        local deadline = os.clock() + seconds
        repeat
            ctx:ThrowIfCancelled()
            if test() then return true end
            task.wait(.05)
            ctx:ThrowIfCancelled()
        until os.clock() >= deadline
        return test()
    end
    local function sleep(ctx, seconds)
        local deadline = os.clock() + seconds
        waitFor(ctx, function() return os.clock() >= deadline end, seconds + .1)
    end
    function m:Run(ctx, getOptions, forceSell, forceRepair)
        ctx:ThrowIfCancelled()
        local function options() return type(getOptions) == "function" and getOptions() or getOptions end
        local opts, before = options(), self:Read()
        local full = before.count >= before.capacity
        local rod = before.rod
        local percent = rod and math.clamp(rod.Current / rod.Max * 100, 0, 100) or 0
        local needSell = (forceSell or full) and opts.Sell and before.sellable > 0
        local needRepair = rod and opts.Repair and rod.Current < rod.Max
            and (forceRepair or percent <= opts.Threshold or rod.Current <= 26)
        local problem
        if full and not needSell then problem = "Mochila cheia: ative a venda ou libere itens bloqueados/minérios." end
        if not rod then problem = problem or "Aguardando dados da vara equipada." end
        if rod and rod.Current <= 0 and not opts.Repair then problem = "Vara quebrada: ative a reparação." end
        if needRepair and not rod.Repairable then
            needRepair = false
            problem = "Esta vara é marcada pelo jogo como não reparável. Escolha outra vara."
        end
        local estimate = rod and math.ceil(rod.Price * .7 * math.clamp(1 - rod.Current / rod.Max, 0, 1)) or 0
        if needRepair and before.silver < estimate and not needSell then
            needRepair = false
            problem = string.format("Prata insuficiente: saldo %.1f; estimativa da interface %d.", before.silver, estimate)
        end
        if not needSell and not needRepair then
            self.status = problem or "Pronto"
            return problem == nil, self.status
        end
        if os.clock() < self.nextAttempt and not forceSell and not forceRepair then return false, self.status end
        self.nextAttempt = os.clock() + 8
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local npcs = workspace:FindFirstChild("NPCS")
        local npc = npcs and npcs:FindFirstChild("Fisherman")
        local prompt = npc and npc:FindFirstChildWhichIsA("ProximityPrompt", true)
        if not humanoid or humanoid.Health <= 0 or not npc or not npc.PrimaryPart or not prompt then
            self.status = "Aguardando personagem e Fisherman carregados."
            return false, self.status
        end
        assert(type(fireproximityprompt) == "function", "Venda/reparação precisam de fireproximityprompt.")
        local original = character:GetPivot()
        local equippedTool = character:FindFirstChild("Fishing Rod")
        local dialog, restored = nil, false
        local talk = require(RS.Client.interactionsv2.prompts.talk)
        local function checkCharacter()
            ctx:ThrowIfCancelled()
            assert(player.Character == character and humanoid.Health > 0, "Personagem mudou durante a manutenção.")
        end
        local function restore()
            if restored then return end
            restored = true
            if dialog and player.PlayerGui:FindFirstChild("ProximityPromptDialog") == dialog then
                local unmount = ups(talk)[1]
                if type(unmount) == "function" then pcall(unmount) end
            end
            if player.Character == character and character.Parent and humanoid.Health > 0 then
                character:PivotTo(original)
                local root = character.PrimaryPart
                if root then root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero end
                if equippedTool and equippedTool.Parent == player.Backpack and not ctx:IsCancelled() then
                    humanoid:EquipTool(equippedTool)
                end
            end
        end
        ctx:Manage(restore)
        ctx:OnCancel(restore)
        self.status = "Visitando Fisherman"
        if equippedTool then humanoid:UnequipTools() end
        local cf = npc.PrimaryPart.CFrame
        local position = (cf * CFrame.new(0, 1, -4)).Position
        character:PivotTo(CFrame.lookAt(position, Vector3.new(cf.Position.X, position.Y, cf.Position.Z)))
        sleep(ctx, .65)
        checkCharacter()
        fireproximityprompt(prompt)
        if not waitFor(ctx, function()
            dialog = player.PlayerGui:FindFirstChild("ProximityPromptDialog")
            return dialog ~= nil
        end, 4) then self.status = "O diálogo do Fisherman não abriu."; restore(); return false, self.status end
        sleep(ctx, .3)
        if needSell and (forceSell or options().Sell) then
            local saleBefore = self:Read()
            self.status = "Vendendo itens não bloqueados da bolsa"
            checkCharacter()
            events:Fire("SellAllFishes")
            if not waitFor(ctx, function()
                local now = self:Read()
                return now.fishCount + now.laganCount < saleBefore.fishCount + saleBefore.laganCount
            end, 5) then self.status = "O servidor não confirmou a venda."; restore(); return false, self.status end
            sleep(ctx, .2)
            local after = self:Read()
            self.sales += 1
            self.sold += math.max(0, saleBefore.fishCount + saleBefore.laganCount - after.fishCount - after.laganCount)
            self.earned += math.max(0, after.silver - saleBefore.silver)
        end
        if needRepair and (forceRepair or options().Repair) then
            local current = self:Read()
            rod = current.rod
            if not rod or rod.Name ~= before.rod.Name then
                self.status = "A vara equipada mudou durante a operação."; restore(); return false, self.status
            end
            estimate = math.ceil(rod.Price * .7 * math.clamp(1 - rod.Current / rod.Max, 0, 1))
            if current.silver < estimate then
                self.status = "Prata insuficiente para a estimativa de reparação."; restore(); return false, self.status
            end
            if rod.Current < rod.Max then
                local revision = self.revision
                self.status = "Reparando " .. rod.Name
                checkCharacter()
                events:Fire("RepairFishingRod", rod.Index)
                if not waitFor(ctx, function()
                    local now = self:Read().rod
                    return self.revision > revision and now and now.Name == rod.Name and now.Current > rod.Current
                end, 5) then self.status = "O servidor não confirmou a reparação."; restore(); return false, self.status end
                sleep(ctx, .2)
                self.repairs += 1
                self.spent += math.max(0, current.silver - self:Read().silver)
            end
        end
        ctx:ThrowIfCancelled()
        restore()
        local after = self:Read()
        self.status = after.count >= after.capacity and "A mochila continua cheia de itens protegidos/minérios." or problem or "Pronto"
        return after.count < after.capacity and problem == nil, self.status
    end
    return m
end

local function main()
    if game.PlaceId ~= 17274762379 then
        error("Este script é para MushYO!.")
    end
    if type(setthreadidentity) == "function" then setthreadidentity(8) end
    local proto = getproto or (debug and debug.getproto)
    local upvalues = getupvalues or (debug and debug.getupvalues)
    assert(type(proto) == "function" and type(upvalues) == "function",
        "Auto Fish precisa de getproto e getupvalues no executor.")
    assert(type(firesignal) == "function", "Auto Fish precisa de firesignal no executor.")

    -- Bootstrap permanente: recebe as próximas atualizações estáveis da API 2.
    local LOADER_URL = "https://raw.githubusercontent.com/ManoGustavo0/RetroBox/main/dist/bootstrap/v2.lua"
    assert(type(loadstring) == "function", "RetroBox API 2 requer loadstring no executor.")
    local loaded, Library = pcall(function()
        local source = game:HttpGet(LOADER_URL)
        local chunk, compileError = loadstring(source, "@RetroBox-bootstrap-v2")
        assert(chunk, compileError)
        return chunk({Channel = "stable"})
    end)
    assert(loaded, "Falha ao carregar RetroBox API 2 pelo bootstrap: " .. tostring(Library))
    assert(type(Library) == "table" and Library.APIVersion == 2 and type(Library.CreateWindow) == "function", "O bootstrap precisa retornar uma RetroBox compatível com a API 2.")

    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local RF = game:GetService("ReplicatedFirst")
    local player = assert(Players.LocalPlayer, "Jogador local indisponível.")
    local env = type(getgenv) == "function" and getgenv() or _G
    local function child(parent, name)
        return assert(parent:WaitForChild(name, 10), "Não carregou: " .. parent:GetFullName() .. "." .. name)
    end
    local rods = child(child(RS, "Client"), "FishingRod")
    local modules = child(RS, "Modules")
    local vars = require(child(rods, "Variables"))
    local events = require(child(modules, "Events"))
    local signals = require(child(modules, "signals"))
    local distance = require(child(modules, "CalculateBobberDistance"))
    local fishConfig = require(child(child(RS, "Configuration"), "Fish"))
    local interactive = child(child(child(RF, "Interface"), "Components"), "Interactive")
    local minigame = require(child(interactive, "HorizontalTarget"))
    assert(type(minigame) == "function" and type(vars.OnStateChanged) == "function",
        "O sistema de pesca mudou ou ainda não está pronto.")

    if env.MushyoHub then env.MushyoHub:Destroy()
    elseif env.MushyoFishRetro then env.MushyoFishRetro:Destroy() end
    if env.__MushFishProbe and env.__MushFishProbe.clean then
        env.__MushFishProbe.clean()
        env.__MushFishProbe = nil
    end

    local hub = {alive = true, casts = 0, caught = 0, hits = 0, escapes = 0,
        accuracy = 0, lastFish = "—", lastWeight = 0, message = "Auto fish desligado"}
    local window = Library:CreateWindow({
        Id = "MushyoAutoFish-" .. game.PlaceId,
        Title = "MushYO Hub", Subtitle = "MushYO Hub · pesca, manutenção e sinuca",
        Icon = "target", Theme = "Retro98", Locale = "pt-BR",
        Settings = true, ShowProfile = true, Launcher = true,
        PixelIcons = true, PixelDecorations = true, DestroyOnClose = false,
        ToggleKey = Enum.KeyCode.RightShift, Parent = child(player, "PlayerGui"),
        ConfigFolder = "RetroBox/MushyoAutoFish/" .. game.PlaceId,
        ConfigVersion = 1, SmoothDragging = false,
        Tooltips = true, TooltipDelay = .2, TextScale = 1, ShowDescriptions = true,
        CallbackExecutor = function(callback, args)
            if type(setthreadidentity) == "function" then setthreadidentity(8) end
            return callback(table.unpack(args, 1, args.n))
        end,
    })
    hub.window = window
    created = hub
    env.MushyoFishRetro = hub
    env.MushyoHub = hub
    function hub:Destroy()
        self.alive = false
        self.window:Destroy()
        if env.MushyoFishRetro == self then env.MushyoFishRetro = nil end
        if env.MushyoHub == self then env.MushyoHub = nil end
    end
    local maintenance = createMaintenance(player, RS, RF, events, fishConfig, upvalues, function(resource, method)
        window:Manage(resource, method)
    end)
    hub.maintenance = maintenance
    local function maintenanceOptions()
        return {Sell = window:GetFlag("mush.sell.enabled") == true,
            Repair = window:GetFlag("mush.repair.enabled") == true,
            Threshold = window:GetFlag("mush.repair.threshold") or 30}
    end

    local function interrupt(cycle)
        if not cycle or cycle.interrupted or not cycle.touched then return end
        cycle.interrupted = true
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and cycle.rod.Parent == character then
            -- Unequipped executa o cleanup nativo: UI, carga, espera e animações.
            pcall(function() humanoid:UnequipTools(); cycle.rod:Deactivate() end)
        end
    end
    window:Manage(function()
        hub.alive = false
        interrupt(hub.cycle)
        if env.MushyoFishRetro == hub then env.MushyoFishRetro = nil end
        if env.MushyoHub == hub then env.MushyoHub = nil end
    end)
    function hub:InSnooker()
        return player.PlayerGui:FindFirstChild("Snooker") ~= nil
    end
    local function pause(ctx, seconds)
        local untilTime = os.clock() + seconds
        repeat
            ctx:ThrowIfCancelled()
            task.wait(math.min(.05, math.max(0, untilTime - os.clock())))
            ctx:ThrowIfCancelled()
        until os.clock() >= untilTime
    end
    local function hasWater(character, power)
        local root = character and character.PrimaryPart
        if not root then return false end
        local origin = (root.CFrame * CFrame.new(0, 0, -distance(power))).Position
        local ray = workspace:Raycast(origin, Vector3.new(0, -25, 0))
        return ray ~= nil and ray.Material == Enum.Material.Water
    end
    local function choosePower(character)
        if not hasWater(character, 0) then return nil end
        for _, power in ipairs({.9, .7, .5, .3, .1}) do
            if hasWater(character, power) then return power end
        end
    end
    local function chargeValue()
        local bindings = upvalues(signals.Fire)[1]
        for _, fn in pairs(type(bindings) == "table" and bindings.ReleaseCharge or {}) do
            if type(fn) == "function" and debug.info(fn, "s"):find("FishingRod.Charge", 1, true) then
                local getter = upvalues(fn)[5]
                if type(getter) == "function" then
                    local value = getter()
                    if type(value) == "number" and value >= 0 and value <= 1 then return value end
                end
            end
        end
        error("Medidor de carga nativo indisponível.")
    end
    local function resolveMinigame()
        -- Proto 6 é InputBegan do HorizontalTarget verificado no MushYO.
        -- Consulta somente este proto, uma vez por minigame, sem varrer getgc.
        local active = proto(minigame, 6, true)
        assert(type(active) == "table", "getproto não retornou os callbacks ativos.")
        for _, fn in ipairs(active) do
            if type(fn) == "function" then
                local u = upvalues(fn)
                local ok, playing, stunned, pointer, target, size, hits, misses = pcall(function()
                    return u[1](), u[2](), u[3](), u[4](), u[5](), u[17](), u[22]()
                end)
                if ok and playing == true and type(stunned) == "boolean"
                    and type(pointer) == "number" and type(target) == "number"
                    and type(size) == "number" and size > 0 and size <= 1
                    and type(hits) == "number" and type(misses) == "number" then
                    return {input = fn, u = u, lastInput = 0}
                end
            end
        end
    end
    local function playMinigame(controller)
        local u = controller.u
        local playing, stunned = u[1](), u[2]()
        local pointer, target, size = u[3](), u[4](), u[5]()
        if playing and not stunned and os.clock() - controller.lastInput >= .075
            and math.abs(pointer - target) <= size * .35 then
            local before = u[17]()
            -- Executa o input nativo somente dentro do alvo real, não da posição suavizada da UI.
            controller.input({UserInputType = Enum.UserInputType.MouseButton1,
                KeyCode = Enum.KeyCode.Unknown}, false)
            hub.hits += math.max(0, u[17]() - before)
            controller.lastInput = os.clock()
        end
        local hits, misses = u[17](), u[22]()
        hub.accuracy = hits + misses > 0 and hits / (hits + misses) * 100 or 0
        hub.miniHits, hub.miniMisses = hits, misses
    end
    local function caughtGui()
        return player.PlayerGui:FindFirstChild("CatchOrReleaseIndicator")
    end
    local function catchButton(gui)
        if not gui then return nil end
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj:IsA("TextButton") and obj.Text == "Catch" then return obj end
        end
    end
    local function bind(name, callback)
        window:Manage(events:Bind(name, function(...)
            if hub.alive and hub.cycle then callback(hub.cycle, ...) end
        end), "Disconnect")
    end
    bind("Catch", function(cycle, duration)
        cycle.miniDeadline = os.clock() + math.max(10, tonumber(duration) or 20) + 12
    end)
    bind("FishCaught", function(cycle, race, bonus)
        if cycle.fish then return end
        cycle.fish = tostring(race)
        hub.caught += 1
        hub.lastFish = cycle.fish
        local info = fishConfig.fishes[race]
        hub.lastWeight = info and info.Weight * (1 + (tonumber(bonus) or 0)) or 0
    end)
    bind("ResetRodState", function(cycle) cycle.resetAt = os.clock() end)
    bind("ChargeFailed", function(cycle) cycle.chargeFailed = true end)

    local function fishingCycle(ctx)
        ctx:ThrowIfCancelled()
        if hub:InSnooker() then
            hub.message = "Pesca suspensa durante a sinuca"
            return {Outcome = "PlayingSnooker"}
        end
        if vars.State == "Idle" or vars.State == "None" then
            local ready, reason = maintenance:Run(ctx, maintenanceOptions)
            if not ready then hub.message = reason; return {Outcome = "WaitingForMaintenance"} end
        end
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 or not character.PrimaryPart then
            hub.message = "Aguardando personagem"
            return {Outcome = "WaitingForCharacter"}
        end
        local rod = character:FindFirstChild("Fishing Rod") or player.Backpack:FindFirstChild("Fishing Rod")
        if not rod or not rod:IsA("Tool") then
            hub.message = "Aguardando Fishing Rod na mochila"
            return {Outcome = "WaitingForRod"}
        end
        if rod.Parent ~= character then
            hub.message = "Equipando vara"
            humanoid:EquipTool(rod)
            pause(ctx, .3)
        end
        if vars.CurrentFishingRod ~= rod or vars.State == "None" then
            hub.message = "Aguardando a vara ficar pronta"
            return {Outcome = "WaitingForEquip"}
        end
        local power
        if vars.State == "Idle" or vars.State == "Charging" then
            power = choosePower(character)
            if not power then
                hub.message = "Fique perto da água e olhe para ela"
                return {Outcome = "WaitingForWater"}
            end
        end
        local cycle = {rod = rod, startedAt = os.clock(), touched = true}
        hub.cycle = cycle
        ctx:Manage(function()
            if not cycle.completed then interrupt(cycle) end
            if hub.cycle == cycle then hub.cycle = nil end
        end)
        ctx:OnCancel(function() interrupt(cycle) end)
        if vars.State == "Idle" then
            hub.message = "Carregando vara"
            ctx:ThrowIfCancelled()
            rod:Activate()
            local deadline = os.clock() + 1.5
            while vars.State == "Idle" and os.clock() < deadline do pause(ctx, .03) end
            assert(vars.State == "Charging", "A vara não iniciou a carga. Confira a água à frente.")
        end
        if vars.State == "Charging" then
            local deadline = os.clock() + 3
            while vars.State == "Charging" and chargeValue() < power and os.clock() < deadline do
                pause(ctx, .03)
            end
            ctx:ThrowIfCancelled()
            assert(vars.State == "Charging" and os.clock() < deadline, "A carga da vara foi interrompida.")
            rod:Deactivate()
            pause(ctx, .15)
            assert(vars.State == "Searching" or vars.State == "Minigame", "O lançamento não foi aceito pela vara.")
            hub.casts += 1
        end

        local deadline, nextResolve = os.clock() + 120, 0
        local controller, button
        while os.clock() < (cycle.miniDeadline or deadline) do
            ctx:ThrowIfCancelled()
            if hub:InSnooker() then hub.message = "Pesca suspensa durante a sinuca"; return {Outcome = "PlayingSnooker"} end
            if player.Character ~= character or humanoid.Health <= 0 or vars.CurrentFishingRod ~= rod then
                hub.message = "A pesca foi interrompida; aguardando a vara"
                return {Outcome = "Interrupted"}
            end
            local gui = caughtGui()
            local showingCatch = gui and #gui:GetChildren() > 0
            if showingCatch then
                hub.message = "Guardando " .. (cycle.fish or "peixe")
                if not button or not button:IsDescendantOf(gui) then button = catchButton(gui) end
                if not cycle.decisionAt and button and button.Visible and button.AbsoluteSize.X > 20 then
                    ctx:ThrowIfCancelled()
                    cycle.decisionAt = os.clock()
                    firesignal(button.Activated)
                end
            elseif vars.State == "Minigame" and not cycle.fish then
                hub.message = "Pescando · minigame automático"
                cycle.resolveDeadline = cycle.resolveDeadline or os.clock() + 3
                if not controller and os.clock() >= nextResolve then
                    controller = resolveMinigame()
                    nextResolve = os.clock() + .25
                end
                assert(controller or os.clock() < cycle.resolveDeadline,
                    "Não foi possível acessar o input nativo do minigame.")
                if controller then playMinigame(controller) end
            elseif vars.State == "Searching" then
                hub.message = "Aguardando fisgada · " .. math.floor(os.clock() - cycle.startedAt) .. " s"
            elseif vars.State == "Idle" then
                if cycle.fish then
                    -- Aguarda também o ResetRodState enviado pelo servidor após a decisão.
                    if cycle.resetAt and (not cycle.decisionAt or cycle.resetAt >= cycle.decisionAt) then
                        cycle.completed = true
                        hub.message = "Capturado: " .. cycle.fish .. " · preparando próxima pesca"
                        return {Outcome = "Caught", Fish = cycle.fish}
                    end
                else
                    cycle.completed = true
                    hub.escapes += 1
                    hub.message = cycle.chargeFailed and "Lançamento falhou; tentando novamente"
                        or "Peixe escapou; preparando próxima pesca"
                    return {Outcome = "Escaped"}
                end
            end
            if cycle.decisionAt then
                assert(os.clock() - cycle.decisionAt < 10, "O servidor não confirmou a decisão da captura.")
            end
            pause(ctx, vars.State == "Minigame" and not cycle.fish and .02 or .1)
        end
        error("A pesca excedeu o tempo de espera. Confira a conexão e ative novamente.")
    end

    local job = window:CreateTask({Id = "mush.fishing.cycle", Interval = .75,
        Group = "mush.fishing", Policy = "Queue", Start = false, OnError = "Stop", Callback = fishingCycle})
    hub.job = job
    function hub:Stop()
        window:SetFlags({["mush.auto.enabled"] = false, ["mush.sell.enabled"] = false,
            ["mush.repair.enabled"] = false, ["mush.snooker.enabled"] = false})
    end
    function hub:GetSnapshot()
        local status = job:GetStatus()
        local data = maintenance:Read()
        return {enabled = status.Requested, inFlight = status.InFlight, task = status.Status,
            state = vars.State, message = self.message, casts = self.casts, caught = self.caught,
            hits = self.hits, escapes = self.escapes, accuracy = self.accuracy,
            lastFish = self.lastFish, lastWeight = self.lastWeight, error = status.LastError,
            inventory = data.count, capacity = data.capacity, silver = data.silver, rod = data.rod,
            sales = maintenance.sales, sold = maintenance.sold, repairs = maintenance.repairs,
            maintenance = maintenance.status, snooker = self.snooker and self.snooker:GetSnapshot()}
    end
    local tab = window:CreateTab({Title = "Auto Fish", Icon = "target", Columns = 1})
    local section = tab:CreateSection({Title = "Pesca automática", Icon = "target"})
    local toggle = section:AddToggle({Id = "mush.auto.enabled", Title = "Ativar Auto Fish",
        Icon = "target", Default = false,
        Tooltip = "Equipa a vara, lança na água, aguarda a fisgada, joga o minigame e guarda o peixe. Desligar cancela a pesca e desequipa a vara.",
        Floating = {Text = "PESCAR", MobileOnly = true, Position = Vector2.new(.04, .65)}})
    toggle:BindTask(job, {Initial = "Control", OnStop = "TurnOff"})
    section:AddSlider({Id = "mush.auto.interval", Title = "Pausa entre tentativas", Icon = "sliders",
        Min = .65, Max = 5, Step = .05, Default = .75, Suffix = " s",
        Tooltip = "Pausa depois que a pesca terminou. A fisgada e a duração do minigame continuam seguindo o jogo."})
    window:Manage(window:GetFlagState("mush.auto.interval"):Subscribe(function(value)
        job:SetInterval(value)
    end, true), "Disconnect")
    local statusLabel = section:AddLabel({Id = "mush.status", Title = "Estado da pesca",
        Icon = "info", Default = hub.message, Height = 65})
    section:AddLabel({Id = "mush.instructions", Title = "Como usar", Icon = "info", Height = 100,
        Default = "Tenha a Fishing Rod na mochila e fique perto da água, olhando para ela.\nAtive Auto Fish; a fisgada pode levar cerca de 45 segundos.\nX oculta o menu. Shift direito ou UI reabre; a pesca continua."})
    local row = section:CreateRow({Gap = 10, StackAt = 440})
    row:AddButton({Id = "mush.stop", Title = "Parar automações", Text = "PARAR", Icon = "close",
        Tooltip = "Desliga pesca, venda, reparação e previsão de sinuca; retorna ao ponto original se estiver visitando o NPC.",
        Callback = function() hub:Stop(); return true end})
    row:AddButton({Id = "mush.unload", Title = "Encerrar script", Text = "ENCERRAR", Icon = "close",
        Tooltip = "Cancela a pesca, remove os listeners e destrói a janela.",
        Callback = function() hub:Destroy(); return true end})

    local maintenanceTab = window:CreateTab({Title = "Manutenção", Icon = "sliders", Columns = 1})
    local saleSection = maintenanceTab:CreateSection({Title = "Venda automática", Icon = "save"})
    saleSection:AddToggle({Id = "mush.sell.enabled", Title = "Vender quando a mochila encher",
        Icon = "save", Default = true,
        Description = "Vende os itens não bloqueados da bolsa pelo fluxo nativo do Fisherman.",
        Tooltip = "Considera peixes, minérios e tesouros na capacidade total (15 ou 50). Visita o Fisherman, abre o diálogo, vende peixes/tesouros não bloqueados e retorna à posição e direção originais."})
    local repairSection = maintenanceTab:CreateSection({Title = "Reparação automática", Icon = "settings"})
    repairSection:AddToggle({Id = "mush.repair.enabled", Title = "Reparar a vara automaticamente",
        Icon = "settings", Default = true,
        Description = "Repara a vara equipada usando créditos de prata do jogo.",
        Tooltip = "A durabilidade é definida pelo servidor. Repara pelo evento nativo e só confirma quando FishingRodsChanged mostra aumento. Varas não reparáveis e saldo insuficiente pausam os novos lançamentos."})
    repairSection:AddSlider({Id = "mush.repair.threshold", Title = "Reparar abaixo de", Icon = "sliders",
        Min = 10, Max = 95, Step = 5, Default = 30, Suffix = "%",
        Tooltip = "Percentual da durabilidade máxima. Também repara com 26 pontos ou menos para reservar margem para a próxima fisgada. O custo estimado segue a interface; o débito real é medido no saldo."})
    local maintenanceLabel = repairSection:AddLabel({Id = "mush.maintenance.status", Title = "Estado da manutenção",
        Icon = "info", Default = "Pronto", Height = 75})
    repairSection:AddLabel({Id = "mush.maintenance.help", Title = "Funcionamento", Icon = "info", Height = 105,
        Default = "A manutenção espera a pesca terminar e compartilha a fila com Auto Fish.\nVisita o Fisherman e volta ao local de pesca automaticamente.\nItens bloqueados são preservados; minérios não são vendidos por esse NPC."})
    local maintenanceJob = window:CreateTask({Id = "mush.maintenance", Interval = 1,
        Group = "mush.fishing", Policy = "Queue", Start = false, OnError = "Continue", Callback = function(ctx)
            ctx:ThrowIfCancelled()
            if hub:InSnooker() then return {Outcome = "PlayingSnooker"} end
            if vars.State ~= "Idle" and vars.State ~= "None" then
                return {Outcome = "WaitingForFishing"}
            end
            local ok, message = maintenance:Run(ctx, maintenanceOptions)
            return {Ready = ok, Message = message}
        end})
    hub.maintenanceJob = maintenanceJob
    local maintainRequested = window:Computed({window:GetFlagState("mush.sell.enabled"),
        window:GetFlagState("mush.repair.enabled")}, function(sell, repair) return sell or repair end)
    window:Manage(maintainRequested:Subscribe(function(enabled)
        if enabled then maintenanceJob:Start() else maintenanceJob:Stop("Manutenção desligada") end
    end, true), "Disconnect")

    local statsTab = window:CreateTab({Title = "Estatísticas", Icon = "grid", Columns = 1})
    local stats = statsTab:CreateSection({Title = "Esta execução", Icon = "star"})
    local values = {caught = window:CreateState(0), casts = window:CreateState(0),
        accuracy = window:CreateState(0), fish = window:CreateState("—"),
        inventory = window:CreateState("—"), durability = window:CreateState(0),
        sales = window:CreateState(0), repairs = window:CreateState(0)}
    local top = stats:CreateRow({Gap = 10, StackAt = 440})
    top:AddStatCard({Id = "mush.stat.caught", Title = "Peixes capturados", Icon = "success",
        State = values.caught, TwoWay = false, Format = "Raw", Subtitle = "Evento FishCaught recebido do servidor"})
    top:AddStatCard({Id = "mush.stat.casts", Title = "Lançamentos", Icon = "target",
        State = values.casts, TwoWay = false, Format = "Raw", Subtitle = "Carga liberada pela vara"})
    local bottom = stats:CreateRow({Gap = 10, StackAt = 440})
    local accuracyCard = bottom:AddStatCard({Id = "mush.stat.accuracy", Title = "Precisão do minigame",
        Icon = "target", State = values.accuracy, TwoWay = false, Format = "Percent", Precision = 1,
        Subtitle = "Acertos e erros medidos pelo jogo"})
    local fishCard = bottom:AddStatCard({Id = "mush.stat.fish", Title = "Último peixe", Icon = "star",
        State = values.fish, TwoWay = false, Format = "Raw", Subtitle = "Aguardando captura"})
    local bagRow = stats:CreateRow({Gap = 10, StackAt = 440})
    bagRow:AddStatCard({Id = "mush.stat.inventory", Title = "Ocupação da mochila", Icon = "folder",
        State = values.inventory, TwoWay = false, Format = "Raw", Subtitle = "Peixes + minérios + tesouros"})
    local rodCard = bagRow:AddStatCard({Id = "mush.stat.durability", Title = "Durabilidade da vara", Icon = "settings",
        State = values.durability, TwoWay = false, Format = "Percent", Precision = 1, Subtitle = "Dados recebidos do servidor"})
    local serviceRow = stats:CreateRow({Gap = 10, StackAt = 440})
    local saleCard = serviceRow:AddStatCard({Id = "mush.stat.sales", Title = "Vendas confirmadas", Icon = "save",
        State = values.sales, TwoWay = false, Format = "Raw", Subtitle = "Aguardando venda"})
    local repairCard = serviceRow:AddStatCard({Id = "mush.stat.repairs", Title = "Reparações confirmadas", Icon = "settings",
        State = values.repairs, TwoWay = false, Format = "Raw", Subtitle = "Aguardando reparação"})
    local taskLabel = stats:AddLabel({Id = "mush.task.status", Title = "Tarefa efetiva", Icon = "terminal", Default = "Inactive"})
    taskLabel:BindState(job.Status, {Property = "Text", TwoWay = false, Transform = function(value)
        local phases = {Inactive = "Desligada", Waiting = "Aguardando próxima tentativa",
            WaitingForGroup = "Aguardando operação anterior", Running = "Em execução",
            Cancelling = "Cancelando", Stopped = "Parada", Failed = "Erro", Destroyed = "Encerrada"}
        return phases[value.Status] or value.Status
    end})
    window:CreateTask({Id = "mush.telemetry", Interval = .25, Start = true, Callback = function(ctx)
        ctx:ThrowIfCancelled()
        local status = job:GetStatus()
        local data = maintenance:Read()
        local maintenanceStatus = maintenanceJob:GetStatus()
        local message = hub.message
        if status.Status == "Failed" then message = "Erro: " .. tostring(status.LastError)
        elseif not status.Active then message = "Auto fish desligado"
        elseif status.Status == "Cancelling" then message = "Cancelando pesca" end
        statusLabel:SetText(message)
        maintenanceLabel:SetText(maintenanceStatus.LastError and "Erro: " .. tostring(maintenanceStatus.LastError) or maintenance.status)
        Library:Batch(function()
            values.caught:Set(hub.caught); values.casts:Set(hub.casts)
            values.accuracy:Set(hub.accuracy); values.fish:Set(hub.lastFish)
            values.inventory:Set(string.format("%d / %d", data.count, data.capacity))
            values.durability:Set(data.rod and math.clamp(data.rod.Current / data.rod.Max * 100, 0, 100) or 0)
            values.sales:Set(maintenance.sales); values.repairs:Set(maintenance.repairs)
        end)
        accuracyCard:SetSubtitle(string.format("Último minigame: %d acertos · %d erros", hub.miniHits or 0, hub.miniMisses or 0))
        fishCard:SetSubtitle(hub.caught > 0 and string.format("Peso observado: %.1f kg", hub.lastWeight) or "Aguardando captura")
        rodCard:SetUnavailable(data.rod == nil, "Vara não identificada")
        rodCard:SetSubtitle(data.rod and string.format("%s · %.1f / %.0f", data.rod.Name, data.rod.Current, data.rod.Max) or "Aguardando dados")
        saleCard:SetSubtitle(string.format("%d itens · +%.1f prata", maintenance.sold, maintenance.earned))
        repairCard:SetSubtitle(string.format("Gasto observado: %.1f prata · saldo: %.1f", maintenance.spent, data.silver))
    end})
    hub.snooker = installSnooker(window, Library, player, RS, proto, upvalues)
    window:Notify({Title = "MushYO Hub", Icon = "target", Kind = "success", Duration = 6,
        Content = "Pronto. Pesca, Manutenção e Sinuca disponíveis. A previsão da sinuca está desligada até você ativar."})
    print("[MushyoHub] pronto · RetroBox " .. Library.Version .. " · pesca, manutenção e sinuca")
end

task.defer(function()
    local ok, err = xpcall(main, function(message) return debug.traceback(tostring(message), 2) end)
    if not ok then
        if created then pcall(function() created:Destroy() end) end
        warn("MushYO Hub: " .. tostring(err))
    end
end)
