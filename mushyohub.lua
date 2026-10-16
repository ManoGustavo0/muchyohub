-- MushYO Hub | Pesca, mineração, manutenção, sinuca e xadrez | RetroBox API 2 Stable
local ChessEngine = (function()
-- Motor local 0x88: busca iterativa, alpha-beta/PVS, quiescência, TT e avaliação posicional.
local E = {}
local band, bxor = bit32.band, bit32.bxor
local abs, floor, min, max = math.abs, math.floor, math.min, math.max
local knight = {33, 31, 18, 14, -14, -18, -31, -33}
local rays = {1, -1, 16, -16, 15, -15, 17, -17}
local values = {100, 320, 335, 500, 950, 0}
local endValues = {120, 310, 335, 520, 940, 0}
local phases = {0, 1, 1, 2, 4, 0}
local names = {"Pawn", "Knight", "Bishop", "Rook", "Queen", "King"}
local codes = {}; for i,n in names do codes[n] = i end
local squares = {}; for r = 0,7 do for f = 0,7 do squares[#squares+1] = r*16+f end end
local seed = 2463534242
local function random()
    seed = bxor(seed, bit32.lshift(seed, 13)); seed = bxor(seed, bit32.rshift(seed,17))
    seed = bxor(seed, bit32.lshift(seed,5)); return seed
end
local zob = {}; for i=1,12 do zob[i]={}; for _,sq in squares do zob[i][sq]=random() end end
local zcastle, zep = {}, {}; for i=0,15 do zcastle[i]=random() end; for i=0,7 do zep[i]=random() end
local zside = random()
local function zi(p) return p>0 and p or 6-p end
local function valid(sq) return sq>=0 and sq<128 and band(sq,0x88)==0 end
local function fromIndex(i) return floor((i-1)/8)*16+(i-1)%8 end
local function toIndex(sq) return floor(sq/16)*8+sq%16+1 end
E.fromIndex, E.toIndex, E.names = fromIndex, toIndex, names

function E.snapshot(native, passant, turn)
    local p={b={}, side=turn=="Black" and -1 or 1, castle=0, ep=passant and fromIndex(passant), half=0, kings={}}
    for _,sq in squares do p.b[sq]=0 end
    for index,piece in native do
        local code=codes[piece.Piece]
        if code then
            local side=piece.Color=="White" and 1 or -1
            local sq=fromIndex(index); p.b[sq]=side*code
            if code==6 then p.kings[side]=sq end
        end
    end
    for _,v in {{1,5,8,1,1,2},{-1,61,64,57,4,8}} do
        local k=native[v[2]]
        if k and k.Piece=="King" and not k.Moved then
            local r=native[v[3]]
            if r and r.Piece=="Rook" and r.Color==k.Color and not r.Moved then p.castle=bit32.bor(p.castle,v[5]) end
            r=native[v[4]]
            if r and r.Piece=="Rook" and r.Color==k.Color and not r.Moved then p.castle=bit32.bor(p.castle,v[6]) end
        end
    end
    local h=zcastle[p.castle]
    for _,sq in squares do local pc=p.b[sq]; if pc~=0 then h=bxor(h,zob[zi(pc)][sq]) end end
    if p.side<0 then h=bxor(h,zside) end
    if p.ep then h=bxor(h,zep[p.ep%16]) end
    p.hash=h
    return p
end

function E.attacked(p, sq, side)
    if not sq then return true end
    local b=p.b; local dir=16*side
    for _,d in {-1,1} do local t=sq-dir+d; if valid(t) and b[t]==side then return true end end
    for _,d in knight do local t=sq+d; if valid(t) and b[t]==2*side then return true end end
    for i,d in rays do
        local t=sq+d; local distance=1
        while valid(t) do
            local pc=b[t]
            if pc~=0 then
                if pc*side>0 then
                    local kind=abs(pc)
                    if kind==5 or (distance==1 and kind==6) or (i<=4 and kind==4) or (i>4 and kind==3) then return true end
                end
                break
            end
            t=t+d; distance=distance+1
        end
    end
    return false
end

local function add(list, from, to, cap, promotion, castle)
    list[#list+1]={from=from,to=to,cap=cap,promo=promotion,castle=castle}
end
local function pawnMove(list,from,to,cap)
    if floor(to/16)==0 or floor(to/16)==7 then
        for _,kind in {5,2,4,3} do add(list,from,to,cap,kind) end
    else add(list,from,to,cap) end
end
function E.pseudo(p)
    local b,side,list=p.b,p.side,{}
    for _,sq in squares do
        local pc=b[sq]
        if pc*side<=0 then continue end
        local kind=abs(pc)
        if kind==1 then
            local dir=16*side; local to=sq+dir
            if valid(to) and b[to]==0 then
                pawnMove(list,sq,to)
                if floor(sq/16)==(side==1 and 1 or 6) and b[to+dir]==0 then add(list,sq,to+dir) end
            end
            for _,d in {-1,1} do
                to=sq+dir+d
                if valid(to) then
                    if b[to]*side<0 and abs(b[to])~=6 then pawnMove(list,sq,to,to)
                    elseif to==p.ep and b[to]==0 and b[to-dir]==-side then pawnMove(list,sq,to,to-dir) end
                end
            end
        elseif kind==2 or kind==6 then
            for _,d in (kind==2 and knight or rays) do
                local to=sq+d
                if valid(to) and b[to]*side<=0 and abs(b[to])~=6 then add(list,sq,to,b[to]~=0 and to or nil) end
            end
            local home=side==1 and 4 or 116
            if kind==6 and sq==home and not E.attacked(p,sq,-side) then
                local kbit=side==1 and 1 or 4; local qbit=side==1 and 2 or 8
                if band(p.castle,kbit)~=0 and b[home+1]==0 and b[home+2]==0 and b[home+3]==side*4
                    and not E.attacked(p,home+1,-side) and not E.attacked(p,home+2,-side) then add(list,sq,home+2,nil,nil,1) end
                if band(p.castle,qbit)~=0 and b[home-1]==0 and b[home-2]==0 and b[home-3]==0 and b[home-4]==side*4
                    and not E.attacked(p,home-1,-side) and not E.attacked(p,home-2,-side) then add(list,sq,home-2,nil,nil,-1) end
            end
        else
            for i,d in rays do
                if (kind==3 and i<=4) or (kind==4 and i>4) then continue end
                local to=sq+d
                while valid(to) do
                    if b[to]*side>0 or abs(b[to])==6 then break end
                    add(list,sq,to,b[to]~=0 and to or nil)
                    if b[to]~=0 then break end
                    to=to+d
                end
            end
        end
    end
    return list
end

function E.make(p,m)
    local b=p.b; local pc=b[m.from]; local captured=m.cap and b[m.cap] or 0
    local u={pc=pc,captured=captured,castle=p.castle,ep=p.ep,half=p.half,hash=p.hash,king=p.kings[p.side]}
    local h=bxor(p.hash,zcastle[p.castle],zob[zi(pc)][m.from],zside)
    if p.ep then h=bxor(h,zep[p.ep%16]) end
    b[m.from]=0
    if m.cap then b[m.cap]=0; h=bxor(h,zob[zi(captured)][m.cap]) end
    local placed=m.promo and m.promo*p.side or pc
    b[m.to]=placed; h=bxor(h,zob[zi(placed)][m.to])
    if abs(pc)==6 then
        p.kings[p.side]=m.to
        p.castle=band(p.castle,p.side==1 and 12 or 3)
    end
    for _,v in {{0,2},{7,1},{112,8},{119,4}} do
        if m.from==v[1] or m.to==v[1] then p.castle=band(p.castle,bit32.bnot(v[2])) end
    end
    if m.castle then
        local rf=m.castle==1 and m.from+3 or m.from-4; local rt=m.from+m.castle
        u.rf,u.rt=rf,rt; b[rt]=b[rf]; b[rf]=0
        h=bxor(h,zob[zi(b[rt])][rf],zob[zi(b[rt])][rt])
    end
    p.ep=abs(pc)==1 and abs(m.to-m.from)==32 and (m.from+m.to)/2 or nil
    if p.ep then h=bxor(h,zep[p.ep%16]) end
    p.half=(abs(pc)==1 or captured~=0) and 0 or p.half+1
    p.side=-p.side; p.hash=bxor(h,zcastle[p.castle])
    return u
end
function E.unmake(p,m,u)
    p.side=-p.side; p.b[m.from]=u.pc; p.b[m.to]=0
    if m.cap then p.b[m.cap]=u.captured end
    if u.rf then p.b[u.rf]=p.b[u.rt]; p.b[u.rt]=0 end
    p.castle,p.ep,p.half,p.hash=u.castle,u.ep,u.half,u.hash
    p.kings[p.side]=u.king
end
function E.legal(p)
    local list={}
    for _,m in E.pseudo(p) do
        local side=p.side; local u=E.make(p,m)
        local legal=not E.attacked(p,p.kings[side],p.side)
        E.unmake(p,m,u)
        if legal then list[#list+1]=m end
    end
    return list
end

function E.evaluate(p)
    local mg,eg,phase=0,0,0
    local files={[1]={},[-1]={}}; local bishops={[1]=0,[-1]=0}; local pawns={[1]={},[-1]={}}
    for _,sq in squares do
        local pc=p.b[sq]; if pc==0 then continue end
        local side=pc>0 and 1 or -1; local kind=abs(pc); local f=sq%16; local rank=floor(sq/16)
        local r=side==1 and rank or 7-rank; local center=7-abs(f-3.5)-abs(r-3.5)
        local a,b=values[kind],endValues[kind]
        phase=phase+phases[kind]
        if kind==1 then
            a=a+r*7+(3.5-abs(f-3.5))*5; b=b+r*r*3+center*2
            files[side][f]=(files[side][f] or 0)+1; pawns[side][#pawns[side]+1]=sq
        elseif kind==2 then a=a+center*13-(r==0 and 15 or 0); b=b+center*8
        elseif kind==3 then a=a+center*7+r*2; b=b+center*5; bishops[side]=bishops[side]+1
        elseif kind==4 then a=a+(r==6 and 22 or 0)+center*2; b=b+center*3
        elseif kind==5 then a=a+center*3; b=b+center*5
        else
            a=a-center*12-r*6+((r==0 and (f<=2 or f>=6)) and 30 or 0)
            b=b+center*13
        end
        mg=mg+side*a; eg=eg+side*b
    end
    for _,side in {1,-1} do
        if bishops[side]>=2 then mg=mg+side*28; eg=eg+side*40 end
        for _,sq in pawns[side] do
            local f=sq%16; local r=floor(sq/16); local advance=side==1 and r or 7-r
            if files[side][f]>1 then mg=mg-side*12; eg=eg-side*18 end
            if not files[side][f-1] and not files[side][f+1] then mg=mg-side*12; eg=eg-side*15 end
            local passed=true
            for _,enemy in pawns[-side] do
                if abs(enemy%16-f)<=1 and (floor(enemy/16)-r)*side>0 then passed=false; break end
            end
            if passed then mg=mg+side*advance*advance*2; eg=eg+side*advance*advance*5 end
        end
        local king=p.kings[side]
        if king then
            for df=-1,1 do
                local shield=king+side*16+df
                if valid(shield) and p.b[shield]==side then mg=mg+side*10 end
            end
        end
    end
    for _,sq in squares do
        local pc=p.b[sq]
        if abs(pc)==4 then
            local side=pc>0 and 1 or -1; local f=sq%16
            if not files[side][f] then mg=mg+side*(files[-side][f] and 12 or 25) end
        end
    end
    phase=min(24,phase)
    return floor((mg*phase+eg*(24-phase))/24)*p.side+10
end

local function code(m) return m.from*1024+m.to*8+(m.promo or 0) end
E.moveCode=code
function E.nativeMove(m)
    return {From=toIndex(m.from),To=toIndex(m.to),Promotion=m.promo and names[m.promo] or nil}
end
function E.search(p,options)
    options=options or {}
    local start=os.clock(); local deadline=start+(options.seconds or 2)
    local ctx=options.context; local cancelled=options.cancelled
    local tt,killers,history={},{},{}
    local repetitions=table.clone(options.repetitions or {}); repetitions[p.hash]=max(1,repetitions[p.hash] or 0)
    local nodes,slice,ttCount=0,start,0
    local MATE,INF=30000,32000
    local function poll()
        nodes=nodes+1
        if nodes%128~=0 then return end
        if ctx then ctx:ThrowIfCancelled() end
        if cancelled and cancelled() then error("MUSH_CHESS_CANCELLED",0) end
        if os.clock()>=deadline then error("MUSH_CHESS_TIMEOUT",0) end
        if os.clock()-slice>.005 then task.wait(); slice=os.clock() end
    end
    local function order(p,list,ttCode,ply)
        for _,m in list do
            local c=code(m); local score=history[c] or 0
            if m.cap then score=10000+values[abs(p.b[m.cap])]*12-values[abs(p.b[m.from])] end
            if m.promo then score=score+9000+values[m.promo] end
            if killers[ply]==c and not m.cap then score=score+8000 end
            if c==ttCode then score=score+1000000 end
            m.order=score
        end
        table.sort(list,function(a,b) if a.order==b.order then return code(a)<code(b) end return a.order>b.order end)
    end
    local function drawn(p)
        if (repetitions[p.hash] or 0)>=3 or p.half>=100 then return true end
        local minors=0
        for _,sq in squares do
            local pc=abs(p.b[sq]); if pc==0 or pc==6 then continue end
            if pc==1 or pc==4 or pc==5 then return false end
            minors=minors+1
        end
        return minors<=1 -- K-K / K+N-K / K+B-K.
    end
    local qsearch
    qsearch=function(p,alpha,beta,ply,qdepth)
        poll()
        if drawn(p) then return 0 end
        if ply>=80 then return E.evaluate(p) end
        local check=E.attacked(p,p.kings[p.side],-p.side)
        local stand=E.evaluate(p)
        local list=E.pseudo(p); order(p,list,nil,ply)
        local legal=0
        local best=check and -INF or stand
        if not check then alpha=max(alpha,stand) end
        -- Confere existência de lances legais também em posições sem capturas: evita avaliar afogamento como vantagem.
        for _,m in list do
            local side=p.side; local u=E.make(p,m)
            if E.attacked(p,p.kings[side],p.side) then E.unmake(p,m,u); continue end
            legal=legal+1
            if not check and stand>=beta then E.unmake(p,m,u); return stand end
            if not check and not m.cap and not m.promo then
                E.unmake(p,m,u); continue
            end
            local score
            if qdepth>=8 then score=-E.evaluate(p)
            else
                repetitions[p.hash]=(repetitions[p.hash] or 0)+1
                score=-qsearch(p,-beta,-alpha,ply+1,qdepth+1)
                repetitions[p.hash]=repetitions[p.hash]-1
            end
            E.unmake(p,m,u)
            best=max(best,score)
            if not check then best=max(best,stand) end
            if best>=beta then return best end
            alpha=max(alpha,best)
        end
        if legal==0 then return check and (-MATE+ply) or 0 end
        if not check then best=max(best,stand) end
        return best
    end
    local negamax
    negamax=function(p,depth,alpha,beta,ply)
        poll()
        if drawn(p) then return 0 end
        if depth<=0 then return qsearch(p,alpha,beta,ply,0) end
        if ply>=80 then return E.evaluate(p) end
        local originalAlpha=alpha; local entry=tt[p.hash]
        if entry and entry.depth>=depth and ply>0 and abs(entry.score)<MATE-100 then
            if entry.bound==0 then return entry.score end
            if entry.bound==1 and entry.score>=beta then return entry.score end
            if entry.bound==-1 and entry.score<=alpha then return entry.score end
        end
        local check=E.attacked(p,p.kings[p.side],-p.side)
        local list=E.pseudo(p); order(p,list,entry and entry.move,ply)
        local legal,best,bestMove=0,-INF,nil
        for _,m in list do
            local side=p.side; local u=E.make(p,m)
            if E.attacked(p,p.kings[side],p.side) then E.unmake(p,m,u); continue end
            legal=legal+1; repetitions[p.hash]=(repetitions[p.hash] or 0)+1
            local score
            if legal==1 then score=-negamax(p,depth-1,-beta,-alpha,ply+1)
            else
                -- PVS: lances posteriores são sondados com janela estreita antes da busca completa.
                score=-negamax(p,depth-1,-alpha-1,-alpha,ply+1)
                if score>alpha and score<beta then score=-negamax(p,depth-1,-beta,-alpha,ply+1) end
            end
            repetitions[p.hash]=repetitions[p.hash]-1; E.unmake(p,m,u)
            if score>best then best,bestMove=score,m end
            alpha=max(alpha,score)
            if alpha>=beta then
                if not m.cap then killers[ply]=code(m); history[code(m)]=min(8000,(history[code(m)] or 0)+depth*depth) end
                break
            end
        end
        if legal==0 then return check and (-MATE+ply) or 0 end
        if ttCount<60000 or tt[p.hash] then
            if not tt[p.hash] then ttCount=ttCount+1 end
            tt[p.hash]={depth=depth,score=best,move=bestMove and code(bestMove),
                bound=best<=originalAlpha and -1 or best>=beta and 1 or 0}
        end
        return best,bestMove
    end
    local rootMoves=E.legal(p)
    if #rootMoves==0 then return {move=nil,depth=0,nodes=0,score=E.attacked(p,p.kings[p.side],-p.side) and -MATE or 0,seconds=0} end
    order(p,rootMoves,nil,0)
    local result={move=rootMoves[1],depth=0,nodes=0,score=0}
    -- Timeout pode interromper make/unmake. Cada iteração trabalha numa cópia isolada.
    for depth=1,(options.depth or 8) do
        local work={b=table.clone(p.b),side=p.side,castle=p.castle,ep=p.ep,half=p.half,hash=p.hash,kings=table.clone(p.kings)}
        local ok,score,move=pcall(negamax,work,depth,-INF,INF,0)
        if not ok then
            local message=tostring(score)
            if message:find("MUSH_CHESS_TIMEOUT",1,true) then break end
            error(score,0)
        end
        if move then result.move,result.depth,result.score=move,depth,score end
        if options.progress then options.progress(result, nodes) end
        if abs(score)>MATE-100 or os.clock()>=deadline then break end
    end
    result.nodes,result.seconds=nodes,os.clock()-start
    return result
end
return E

end)()
local installChess = (function()
return function(window, Library, player, RS, Engine)
    local controller = require(RS.Client.Controllers.Chess)
    local Rules = require(RS.Configuration.Chess).Rules
    local Blink = require(RS.Blink.Client).Chess
    assert(type(controller.Boards)=="table" and type(Rules.Legal)=="function" and type(Blink.Move.Fire)=="function",
        "O contrato do xadrez mudou.")
    local names={Pawn="Peão",Knight="Cavalo",Bishop="Bispo",Rook="Torre",Queen="Rainha",King="Rei"}
    local letters={Pawn="p",Knight="n",Bishop="b",Rook="r",Queen="q",King="k"}
    local chess={alive=true,message="Auto play desligado",moves=0,pending=nil,histories={}}
    local scope=window:CreateScope()
    local folder=Instance.new("Folder"); folder.Name="MushyoHub_ChessPreview"; folder.Parent=workspace; scope:Add(folder)
    local mouse=player:GetMouse()
    local colors={move=Color3.fromRGB(65,230,140),capture=Color3.fromRGB(255,85,100),danger=Color3.fromRGB(255,170,45),selected=Color3.fromRGB(80,190,255)}
    local markers={}
    local tab=window:CreateTab({Title="Xadrez",Icon="crown",Columns=1})
    local preview=tab:CreateSection({Title="Prévia das peças",Icon="eye"})
    local previewToggle=preview:AddToggle({Id="mush.chess.preview",Title="Mostrar movimentos e capturas",Icon="eye",Default=false,
        Tooltip="Passe o mouse numa peça ou selecione-a no tabuleiro. Usa as regras nativas: bloqueios, xeque, roque, en passant e promoção."})
    preview:AddToggle({Id="mush.chess.rooks-only",Title="Mostrar somente torres",Icon="crown",Default=false,
        Tooltip="Filtra a prévia para torres. Desligado, funciona com todas as peças do xadrez."})
    preview:AddToggle({Id="mush.chess.danger",Title="Sinalizar destinos atacados",Icon="shield",Default=true,
        Tooltip="Laranja indica que o adversário ataca a casa depois do lance. Isso não significa necessariamente uma jogada ruim: trocas e sacrifícios podem ser corretos."})
    local previewLabel=preview:AddLabel({Id="mush.chess.preview-status",Title="Peça e movimentos",Icon="info",Default="Prévia desligada"})
    preview:AddLabel({Id="mush.chess.legend",Title="Legenda",Icon="palette",
        Default="Azul: peça analisada. Verde: movimento legal. Vermelho: captura.\nLaranja: destino atacado; a etiqueta informa se também captura.\nPasse o mouse nas peças ou use a seleção normal do jogo."})
    local rows=preview:AddDataTable({Id="mush.chess.legal",Title="Lances da peça",Rows={},Height=210,Columns={
        {Key="Square",Title="Casa",Width=65},{Key="Capture",Title="Captura",Width=110},
        {Key="Risk",Title="Destino",Width=105},{Key="Special",Title="Especial",Width=105}}})
    local auto=tab:CreateSection({Title="Auto play inteligente",Icon="crown"})
    local autoToggle=auto:AddToggle({Id="mush.chess.auto",Title="Jogar xadrez automaticamente",Icon="crown",Default=false,
        Tooltip="Joga somente pelo seu lado e na sua vez. Avalia material, desenvolvimento, segurança do rei e respostas do adversário; verifica capturas e promoções. Não garante vitória."})
    auto:AddSlider({Id="mush.chess.seconds",Title="Tempo de análise por jogada",Icon="clock",Min=.5,Max=8,Step=.5,Default=3,Suffix=" s",
        Tooltip="Mais tempo permite pesquisar mais respostas. A busca cede tempo ao jogo e pode ser cancelada ao desligar."})
    auto:AddSlider({Id="mush.chess.depth",Title="Limite de profundidade",Icon="sliders",Min=2,Max=10,Step=1,Default=8,Suffix=" meios-lances",
        Tooltip="Cada meio-lance é uma jogada de um lado. A busca aumenta a profundidade progressivamente e respeita o tempo escolhido."})
    local autoLabel=auto:AddLabel({Id="mush.chess.status",Title="Estado da IA",Icon="notification",Default=chess.message})
    local resultLabel=auto:AddLabel({Id="mush.chess.analysis",Title="Última análise",Icon="target",Default="Nenhuma posição analisada"})
    local countCard=auto:AddStatCard({Id="mush.chess.moves",Title="Jogadas confirmadas",Icon="success",Value=0})
    auto:AddLabel({Id="mush.chess.help",Title="Como usar",Icon="info",
        Default="Sente na mesa de xadrez e aguarde outro jogador. Ative a prévia e/ou o auto play.\n"
            .."A IA usa busca local com avaliação posicional e cálculo de trocas; o computador e o tempo de análise limitam sua força.\n"
            .."Pesca e visitas ao Fisherman pausam enquanto você estiver na mesa. X oculta o menu; PARAR desliga a IA."})

    local function squareName(index)
        return string.char(97+(index-1)%8)..tostring(math.floor((index-1)/8)+1)
    end
    local function key(b)
        local t={tostring(b.Id),b.Turn or "",tostring(b.Passant or 0)}
        for i=1,64 do
            local p=b.State[i]
            t[#t+1]=p and ((p.Color=="White" and string.upper(letters[p.Piece]) or letters[p.Piece])..(p.Moved and "1" or "0")) or ".."
        end
        return table.concat(t)
    end
    local function ownBoard()
        for _,b in controller.Boards do if b.Side and b.Model and b.Model.Parent then return b end end
    end
    function chess:IsPlaying()
        local b=ownBoard(); return b~=nil and not b.Over
    end
    local function previewBoard()
        local own=ownBoard(); if own then return own end
        local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local pos=root and root.Position or workspace.CurrentCamera.CFrame.Position
        local closest,distance=nil,80
        for _,b in controller.Boards do
            local d=(b.Center-pos).Magnitude
            if d<distance and next(b.State) then closest,distance=b,d end
        end
        return closest
    end
    local function clear()
        for _,v in markers do v.part.Transparency=1; v.gui.Enabled=false end
    end
    local function mark(b,index,color,text)
        local square=b.Squares[index]; if not square then return end
        local v=markers[index]
        if not v then
            local part=Instance.new("Part"); part.Name="ChessSquare_"..index; part.Anchored=true
            part.CanCollide=false; part.CanTouch=false; part.CanQuery=false; part.CastShadow=false
            part.Material=Enum.Material.Neon; part.Parent=folder
            local gui=Instance.new("BillboardGui"); gui.Size=UDim2.fromOffset(150,32); gui.AlwaysOnTop=true
            gui.MaxDistance=100; gui.StudsOffsetWorldSpace=Vector3.new(0,.4,0); gui.Adornee=part; gui.Parent=part
            local label=Instance.new("TextLabel"); label.Size=UDim2.fromScale(1,1); label.BackgroundTransparency=1
            label.TextColor3=Color3.new(1,1,1); label.TextStrokeTransparency=.1; label.TextStrokeColor3=Color3.new(0,0,0)
            label.TextSize=12; label.Font=Enum.Font.Code; label.Parent=gui
            v={part=part,gui=gui,label=label}; markers[index]=v
        end
        v.part.Size=Vector3.new(square.Size.X*.87,.025,square.Size.Z*.87)
        v.part.CFrame=square.CFrame*CFrame.new(0,square.Size.Y/2+.025,0)
        v.part.Color=color; v.part.Transparency=.35; v.label.Text=text; v.gui.Enabled=true
    end
    local function hovered(b)
        local target=mouse.Target; if not target then return end
        for index,piece in b.Pieces do if target==piece.Part then return index end end
        for index,part in b.Squares do if part==target and b.State[index] then return index end end
    end
    local lastPreview
    local previewJob=window:CreateTask({Id="mush.chess.preview-task",Interval=.12,Start=false,OnError="Continue",Callback=function(ctx)
        ctx:ThrowIfCancelled()
        local b=previewBoard()
        if not b or b.Over or not next(b.State) then
            clear(); rows:SetRows({}); previewLabel:SetText("Sente numa mesa e aguarde a partida começar"); lastPreview=nil; return
        end
        local selected=hovered(b) or b.Selected or b.Cursor
        local piece=selected and b.State[selected]
        if not piece or (window:GetFlag("mush.chess.rooks-only") and piece.Piece~="Rook") then
            clear(); rows:SetRows({}); previewLabel:SetText("Passe o mouse numa "..(window:GetFlag("mush.chess.rooks-only") and "torre" or "peça")); lastPreview=nil; return
        end
        local current=key(b)..":"..selected..":"..tostring(window:GetFlag("mush.chess.danger"))
        if current==lastPreview then return end
        lastPreview=current; clear()
        local legal=Rules.Legal(b.State,b.Passant,selected)
        local list,count,captures={},0,0
        mark(b,selected,colors.selected,(names[piece.Piece] or piece.Piece).." · "..squareName(selected))
        for to,m in legal do
            local captured=m.Capture and b.State[m.Capture]
            local after=Rules.CloneBoard(b.State); Rules.Apply(after,m,m.Promotion and "Queen" or nil)
            local opponent=piece.Color=="White" and "Black" or "White"
            local danger=Rules.Attacked(after,to,opponent)
            local color=window:GetFlag("mush.chess.danger") and danger and colors.danger or captured and colors.capture or colors.move
            local text=captured and "CAPTURA "..string.upper(names[captured.Piece] or captured.Piece) or squareName(to)
            if danger and window:GetFlag("mush.chess.danger") then text=text.." · ATACADA" end
            mark(b,to,color,text)
            count=count+1; if captured then captures=captures+1 end
            list[#list+1]={Id=tostring(to),Square=squareName(to),Capture=captured and names[captured.Piece] or "—",
                Risk=danger and "Atacado" or "Não atacado",Special=m.Castle and "Roque" or m.Promotion and "Promoção" or
                    m.Capture and m.Capture~=to and "En passant" or "—"}
        end
        table.sort(list,function(a,c)return a.Square<c.Square end); rows:SetRows(list)
        previewLabel:SetText(string.format("%s %s em %s • %d lances legais • %d capturas%s",names[piece.Piece],
            piece.Color=="White" and "branca" or "preta",squareName(selected),count,captures,
            Rules.InCheck(b.State,piece.Color) and " • rei em xeque" or ""))
    end})
    previewToggle:BindTask(previewJob,{Initial="Control",OnStop="TurnOff"})
    scope:Add(window:GetFlagState("mush.chess.preview"):Subscribe(function(enabled)
        lastPreview=nil
        if not enabled then clear(); rows:SetRows({}); previewLabel:SetText("Prévia desligada") end
    end),"Disconnect")

    local job
    job=window:CreateTask({Id="mush.chess.auto-task",Interval=.2,Start=false,OnError="Stop",Callback=function(ctx)
        ctx:ThrowIfCancelled()
        local b=ownBoard()
        if not b then chess.pending=nil; chess.message="Sente numa mesa de xadrez"; return end
        if b.Over then
            local sent=chess.pending
            local moved=sent and sent.id==b.Id and b.State[sent.move.To]
            if sent and key(b)~=sent.key and moved and moved.Color==b.Side then chess.moves=chess.moves+1 end
            chess.pending=nil; chess.histories[b.Id]=nil; chess.message="Partida encerrada; aguardando a próxima"; return
        end
        if not b.Opponent or not next(b.State) then chess.pending=nil; chess.histories[b.Id]=nil; chess.message="Aguardando adversário"; return end
        local current=key(b)
        local pending=chess.pending
        if pending then
            if pending.id~=b.Id then chess.pending=nil
            elseif current~=pending.key then
                local moved=b.State[pending.move.To]
                if b.Turn~=b.Side and moved and moved.Color==b.Side then chess.moves=chess.moves+1 end
                chess.pending=nil
            else
                if pending.move.Promotion then
                    local gui=player.PlayerGui:FindFirstChild("ChessPromotion")
                    local button=gui and gui:FindFirstChild(pending.move.Promotion,true)
                    if button and button:IsA("GuiButton") and button.Visible and not pending.promotionSent then
                        ctx:ThrowIfCancelled(); pending.promotionSent=true
                        -- Usa a escolha nativa para também fechar corretamente o diálogo.
                        firesignal(button.Activated)
                    end
                end
                local elapsed=os.clock()-pending.at
                if elapsed>4 and not pending.requested then pending.requested=true; Blink.Request.Fire() end
                if elapsed>9 then error("O servidor não confirmou a jogada; auto play pausado para evitar repetição.") end
                chess.message="Aguardando o servidor confirmar "..squareName(pending.move.From).." → "..squareName(pending.move.To)
                return
            end
        end
        if b.Turn~=b.Side then chess.message="Aguardando a vez do adversário"; return end
        local position=Engine.snapshot(b.State,b.Passant,b.Turn)
        local hist=chess.histories[b.Id]
        if not hist then hist={counts={},keys={}}; chess.histories[b.Id]=hist end
        -- Registra também a posição atual; a telemetria acompanha as posições entre os turnos.
        if hist.last~=current then
            hist.counts[position.hash]=(hist.counts[position.hash] or 0)+1
            hist.last=current; hist.keys[#hist.keys+1]=position.hash
            if #hist.keys>256 then local old=table.remove(hist.keys,1); hist.counts[old]=math.max(0,(hist.counts[old] or 0)-1) end
        end
        chess.message="Analisando a posição..."
        local ok,result=pcall(Engine.search,position,{context=ctx,seconds=window:GetFlag("mush.chess.seconds"),
            depth=window:GetFlag("mush.chess.depth"),repetitions=hist.counts,
            cancelled=function() return not chess.alive or b.Over or b.Side~=b.Turn or key(b)~=current end,
            progress=function(r,nodes)
                chess.message=string.format("Analisando • profundidade %d • %d posições",r.depth,nodes)
            end})
        if not ok then
            if ctx:IsCancelled() or not chess.alive or key(b)~=current or ownBoard()~=b or b.Over or b.Side~=b.Turn then return end
            error(result)
        end
        ctx:ThrowIfCancelled()
        if ownBoard()~=b or b.Over or b.Turn~=b.Side or key(b)~=current then return end
        if not result.move then chess.message="Nenhum lance legal disponível"; return end
        local move=Engine.nativeMove(result.move)
        local native=Rules.Legal(b.State,b.Passant,move.From)[move.To]
        if not native or not b.State[move.From] or b.State[move.From].Color~=b.Side then
            error("A jogada calculada não passou pela validação nativa; nenhum lance foi enviado.")
        end
        local evaluation=math.abs(result.score)>29000 and "mate calculado" or string.format("%+.2f peões",result.score/100)
        resultLabel:SetText(string.format("%s → %s%s • %s\nProfundidade %d • %d posições • %.2fs",
            squareName(move.From),squareName(move.To),move.Promotion and " = "..names[move.Promotion] or "",evaluation,result.depth,result.nodes,result.seconds))
        chess.analysis={move=move,score=result.score,depth=result.depth,nodes=result.nodes,seconds=result.seconds}
        ctx:ThrowIfCancelled()
        chess.pending={id=b.Id,key=current,at=os.clock(),move=move}
        Blink.Move.Fire(b.Id,{X=(move.From-1)%8+1,Y=math.floor((move.From-1)/8)+1},
            {X=(move.To-1)%8+1,Y=math.floor((move.To-1)/8)+1})
        chess.message="Jogada enviada; aguardando confirmação"
    end})
    autoToggle:BindTask(job,{Initial="Control",OnStop="TurnOff"})
    chess.job=job
    scope:Add(window:GetFlagState("mush.chess.auto"):Subscribe(function(value)
        if not value then chess.message="Auto play desligado" end
    end),"Disconnect")
    window:CreateTask({Id="mush.chess.telemetry",Interval=.25,Start=true,OnError="Continue",Callback=function(ctx)
        ctx:ThrowIfCancelled()
        local status=job:GetStatus()
        autoLabel:SetText(status.LastError and "Erro: "..tostring(status.LastError) or chess.message)
        countCard:SetValue(chess.moves)
        local b=ownBoard(); local hist=b and chess.histories[b.Id]
        if hist and not b.Over and next(b.State) then
            local current=key(b)
            if hist.last~=current then
                local p=Engine.snapshot(b.State,b.Passant,b.Turn)
                hist.counts[p.hash]=(hist.counts[p.hash] or 0)+1; hist.last=current; hist.keys[#hist.keys+1]=p.hash
                if #hist.keys>256 then local old=table.remove(hist.keys,1); hist.counts[old]=math.max(0,(hist.counts[old] or 0)-1) end
            end
        end
    end})
    function chess:GetSnapshot()
        local b=ownBoard()
        return {status=self.message,playing=self:IsPlaying(),side=b and b.Side,turn=b and b.Turn,
            confirmedMoves=self.moves,analysis=self.analysis,pending=self.pending~=nil,job=job:GetStatus()}
    end
    scope:Add(function() chess.alive=false; clear() end)
    return chess
end

end)()
local installMining=(function()
-- Mineração pelo fluxo nativo da Pickaxe: ativação, círculos, guardar minério e Miner.
return function(hub, window, Library, player, RS, RF, events, ups)
    local CS=game:GetService("CollectionService")
    local constants=require(RS.Configuration.pickaxes.constants)
    local fishConfig=require(RS.Configuration.Fish)
    require(RS.Configuration.Dialogs.Miner)
    local inventory=ups(require(RF.Interface.Build.FishInventory).CreateWindow)
    assert(type(inventory[12])=="function", "O inventário de minérios mudou.")
    assert(type(getconnections)=="function" and type(firesignal)=="function", "Mineração precisa de getconnections e firesignal.")
    local handlers=ups(events.Bind)[1]
    local m={alive=true,data={pickaxes={}},ores={},locked={},oreRevision=0,revision=0,
        collected=0,clicks=0,swings=0,sales=0,sold=0,repairs=0,earned=0,spent=0,
        message="Auto mineração desligado",blocked=setmetatable({},{__mode="k"}),nextVisit=0}
    local function size(t) local n=0; for _,v in pairs(t or {}) do if type(v)=="table" then n=n+1 end end; return n end
    for _,fn in pairs(handlers.MiningDataChanged or {}) do
        if debug.info(fn,"s"):find("Pickaxe.Client",1,true) then
            local data=ups(fn)[1]
            if type(data)=="table" then m.data=data; m.ores=data.ores or {}; m.locked=data.lockedOres or {} end
        end
    end
    for _,fn in pairs(handlers.LockedOresUpdated or {}) do
        if debug.info(fn,"s"):find("vide",1,true) then local ok,value=pcall(fn); if ok and type(value)=="table" then m.locked=value end end
    end
    window:Manage(events:Bind("MiningDataChanged",function(data)
        if type(data)=="table" then m.data=data; m.revision=m.revision+1 end
    end),"Disconnect")
    window:Manage(events:Bind("OresChanged",function(ores)
        if type(ores)~="table" then return end
        local gained=size(ores)-size(m.ores)
        if m.session and gained>0 then m.collected=m.collected+gained end
        m.ores=ores; m.oreRevision=m.oreRevision+1
    end),"Disconnect")
    window:Manage(events:Bind("LockedOresUpdated",function(locked) if type(locked)=="table" then m.locked=locked end end),"Disconnect")
    events:Fire("RequestMiningData")
    events:Fire("RequestOresChanged")

    local function read()
        local shared=hub.maintenance:Read()
        local equipped=m.data.equipped
        local owned=equipped and m.data.pickaxes and m.data.pickaxes[equipped]
        local def=equipped and constants.All[equipped]
        local pick=owned and def and {name=equipped,current=tonumber(owned.durability) or 0,max=def.MaxDurability,
            price=def.Price,breakable=def.Breakable~=false,rarity=def.Rarity} or nil
        local sellable=0
        for index,ore in pairs(m.ores) do
            local id=ore.Index or index
            if not m.locked[id] and not m.locked[tostring(id)] then sellable=sellable+1 end
        end
        return {count=shared.count,capacity=shared.capacity,silver=shared.silver,ores=size(m.ores),sellable=sellable,pickaxe=pick}
    end
    m.Read=read
    local function sleep(ctx,seconds)
        local deadline=os.clock()+seconds
        repeat ctx:ThrowIfCancelled(); task.wait(math.min(.05,math.max(0,deadline-os.clock()))) until os.clock()>=deadline
        ctx:ThrowIfCancelled()
    end
    local function waitFor(ctx,test,seconds)
        local deadline=os.clock()+seconds
        repeat ctx:ThrowIfCancelled(); if test() then return true end; task.wait(.05) until os.clock()>=deadline
        ctx:ThrowIfCancelled(); return test()
    end
    local function character()
        local c=player.Character; local h=c and c:FindFirstChildOfClass("Humanoid"); local r=c and c:FindFirstChild("HumanoidRootPart")
        if h and r and h.Health>0 then return c,h,r end
    end
    local function nativeController(tool)
        for _,conn in ipairs(getconnections(tool.Activated)) do
            local fn=conn.Function
            if type(fn)=="function" and debug.info(fn,"s"):find("Pickaxe.Client",1,true) then
                local u=ups(fn)
                if type(u[2])=="function" and type(u[3])=="function" then
                    local ok,a,b=pcall(function() return u[2](),u[3]() end)
                    if ok and type(a)=="boolean" and type(b)=="boolean" then
                        return {tool=tool,active=u[2],result=u[3]}
                    end
                end
            end
        end
    end
    local function value(getter)
        if type(getter)~="function" then return false end
        local ok,result=pcall(getter); return ok and result==true
    end
    function m:IsBusy()
        local c=self.controller
        return self.session~=nil or self.cleaning==true or (c~=nil and (value(c.active) or value(c.result)))
    end
    local function resultButton(text)
        for _,gui in ipairs(player.PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Name~="Pickaxe" and gui.Name~="ProximityPromptDialog" and not gui.Name:find("RetroBox",1,true) then
                for _,button in ipairs(gui:GetDescendants()) do
                    if button:IsA("TextButton") and button.Text==text and button.Visible and button.AbsoluteSize.X>5 then return button end
                end
            end
        end
    end
    local function cleanSession(session,cancelled)
        if m.session~=session then return end
        m.cleaning=true
        local deadline=os.clock()+5.8
        -- Unequipped não cancela o minigame desta ferramenta. Deixa o timeout nativo liberar o personagem.
        if cancelled and os.clock()-(session.lastSwing or 0)<.8 then task.wait(.8) end
        while player.Character==session.character and os.clock()<deadline and value(session.controller.active) do task.wait(.08) end
        if value(session.controller.result) then
            local release=resultButton("Release")
            if release then pcall(firesignal,release.Activated) end
        end
        if cancelled and player.Character==session.character and session.humanoid.Health>0 and session.tool.Parent==session.character then
            pcall(function() session.humanoid:UnequipTools() end)
        end
        m.session=nil; m.cleaning=false
    end

    function m:Maintain(ctx,forceSell,forceRepair)
        ctx:ThrowIfCancelled()
        if hub:InBoardGame() then return false,"Manutenção pausada durante o minigame de mesa" end
        local before=read(); local pick=before.pickaxe
        if not pick then return false,"Aguardando dados da picareta equipada" end
        local loss=constants.DurabilityCost[pick.rarity]
        local reserve=loss and loss.Max or 5
        local percent=pick.current/pick.max*100
        local repair=pick.breakable and pick.current<pick.max and (forceRepair or (window:GetFlag("mush.mine.repair") and
            (percent<=(window:GetFlag("mush.mine.threshold") or 30) or pick.current<=reserve)))
        local price=math.ceil(pick.price*.4*math.clamp(1-pick.current/pick.max,0,1))
        local sell=(forceSell or window:GetFlag("mush.mine.sell")) and before.sellable>0 and
            (forceSell or before.count>=before.capacity or (repair and before.silver<price))
        if not sell and not repair then
            if before.count>=before.capacity then return false,"Mochila cheia: sem minérios desbloqueados para vender" end
            if pick.current<=0 then return false,"Picareta quebrada: ative a reparação" end
            return true,"Pronto"
        end
        if repair and before.silver<price and not sell then return false,"Prata insuficiente para reparar a picareta" end
        if not forceSell and not forceRepair and os.clock()<m.nextVisit then return false,"Aguardando a próxima tentativa no Miner" end
        m.nextVisit=os.clock()+6
        local c,h,root=character()
        local npcs=workspace:FindFirstChild("NPCS"); local npc=npcs and npcs:FindFirstChild("Miner")
        local prompt=npc and npc:FindFirstChildWhichIsA("ProximityPrompt",true)
        if not c or not npc or not npc.PrimaryPart or not prompt then return false,"Aguardando personagem e NPC Miner" end
        if h.SeatPart then return false,"Saia do assento antes de visitar o Miner" end
        assert(type(fireproximityprompt)=="function","Visitar o Miner precisa de fireproximityprompt.")
        local original=c:GetPivot(); local equipped=c:FindFirstChildOfClass("Tool"); local dialog; local restored=false
        local talk=require(RS.Client.interactionsv2.prompts.talk)
        local function restore()
            if restored then return end; restored=true
            if dialog and player.PlayerGui:FindFirstChild("ProximityPromptDialog")==dialog then
                local unmount=ups(talk)[1]; if type(unmount)=="function" then pcall(unmount) end
            end
            if player.Character==c and c.Parent and h.Health>0 then
                c:PivotTo(original); root.AssemblyLinearVelocity=Vector3.zero
                if equipped and equipped.Parent==player.Backpack and not ctx:IsCancelled() then h:EquipTool(equipped) end
            end
        end
        ctx:Manage(restore)
        local ok,reason=pcall(function()
            m.message="Visitando o Miner"
            h:UnequipTools()
            local cf=npc.PrimaryPart.CFrame; local p=(cf*CFrame.new(0,1,-4)).Position
            c:PivotTo(CFrame.lookAt(p,Vector3.new(cf.Position.X,p.Y,cf.Position.Z)))
            sleep(ctx,.65); fireproximityprompt(prompt)
            assert(waitFor(ctx,function() dialog=player.PlayerGui:FindFirstChild("ProximityPromptDialog"); return dialog~=nil end,4),"O diálogo do Miner não abriu")
            sleep(ctx,.2)
            if sell then
                local previous=read(); local rev=m.oreRevision
                m.message="Vendendo minérios no Miner"
                if next(m.locked)==nil then
                    events:Fire("SellAllOres")
                    assert(waitFor(ctx,function() return m.oreRevision>rev and size(m.ores)<previous.ores end,4),"O servidor não confirmou a venda dos minérios")
                else
                    local ids={}
                    for index,ore in pairs(m.ores) do local id=ore.Index or index
                        if not m.locked[id] and not m.locked[tostring(id)] then ids[#ids+1]=id end
                    end
                    table.sort(ids,function(a,b)return tonumber(a)>tonumber(b)end)
                    for _,id in ids do
                        ctx:ThrowIfCancelled()
                        local n=size(m.ores); events:Fire("SellOre",id)
                        assert(waitFor(ctx,function()return size(m.ores)<n end,3),"Uma venda individual não foi confirmada")
                    end
                end
                sleep(ctx,.15)
                local after=read(); m.sales=m.sales+1; m.sold=m.sold+math.max(0,previous.ores-after.ores)
                m.earned=m.earned+math.max(0,after.silver-previous.silver)
            end
            if repair then
                local previous=read(); local current=previous.pickaxe
                assert(current and current.name==pick.name,"A picareta equipada mudou durante a visita")
                local cost=math.ceil(current.price*.4*math.clamp(1-current.current/current.max,0,1))
                assert(previous.silver>=cost,"Prata insuficiente para reparar a picareta")
                local rev=m.revision; m.message="Reparando "..current.name
                events:Fire("RepairPickaxe",current.name)
                assert(waitFor(ctx,function()
                    local updated=read().pickaxe
                    return m.revision>rev and updated and updated.name==current.name and updated.current>current.current
                end,4),"O servidor não confirmou a reparação")
                sleep(ctx,.15); m.repairs=m.repairs+1; m.spent=m.spent+math.max(0,previous.silver-read().silver)
            end
        end)
        restore()
        if not ok then if ctx:IsCancelled() then ctx:ThrowIfCancelled() end; return false,tostring(reason) end
        local after=read()
        if after.count>=after.capacity then return false,"Mochila ainda cheia de itens protegidos ou de outros tipos" end
        return true,"Manutenção concluída; voltando à mineração"
    end

    local function chooseOre(root)
        if m.target and m.target.Parent and m.target:HasTag("OreModel") and (m.blocked[m.target] or 0)<os.clock() then return m.target end
        local best,nearest
        for _,ore in ipairs(CS:GetTagged("OreModel")) do
            if ore:IsA("Model") and ore:IsDescendantOf(workspace) and (m.blocked[ore] or 0)<os.clock() then
                local tagged=false; for _,part in ore:GetChildren() do if part:IsA("BasePart") and part:HasTag("Ore") then tagged=true;break end end
                if tagged then local d=(ore:GetPivot().Position-root.Position).Magnitude
                    if not nearest or d<nearest then best,nearest=ore,d end
                end
            end
        end
        m.target=best; return best
    end
    local function approach(c,h,root,target)
        local cf,box=target:GetBoundingBox(); local center=cf.Position
        local delta=Vector3.new(root.Position.X-center.X,0,root.Position.Z-center.Z)
        local direction=delta.Magnitude>.1 and delta.Unit or Vector3.new(0,0,1)
        local extent=(math.abs(direction:Dot(cf.RightVector))*box.X+math.abs(direction:Dot(cf.LookVector))*box.Z)/2
        local p=center+direction*(extent+1.8)
        local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={c,target}
        local floorHit=workspace:Raycast(p+Vector3.new(0,8,0),Vector3.new(0,-35,0),params)
        p=Vector3.new(p.X,(floorHit and floorHit.Position.Y or center.Y-box.Y/2)+h.HipHeight+root.Size.Y/2,p.Z)
        root.CFrame=CFrame.lookAt(p,Vector3.new(center.X,p.Y,center.Z)); root.AssemblyLinearVelocity=Vector3.zero
    end
    local function circle()
        local gui=player.PlayerGui:FindFirstChild("Pickaxe"); if not gui then return end
        for _,button in ipairs(gui:GetDescendants()) do
            if button:IsA("ImageButton") and button.Visible and button.AbsoluteSize.X>5 and
                button:FindFirstChild("AnimatedWhiteCircle") and button:FindFirstChild("MiddleCircle") then return button end
        end
    end
    local function cycle(ctx)
        ctx:ThrowIfCancelled()
        if hub:InBoardGame() then m.message="Mineração pausada durante o minigame de mesa"; return end
        local ready,reason=m:Maintain(ctx,false,false)
        if not ready then m.message=reason; return end
        local c,h,root=character()
        if not c then m.message="Aguardando personagem"; return end
        if h.SeatPart then m.message="Saia do assento para minerar"; return end
        local tool=c:FindFirstChild("Pickaxe") or player.Backpack:FindFirstChild("Pickaxe")
        if not tool then m.message="Aguardando Pickaxe na mochila"; return end
        local target=chooseOre(root)
        if not target then m.message="Nenhum minério carregado: aproxime-se das minas"; return end
        if not window:GetFlag("mush.mine.move") and (target:GetPivot().Position-root.Position).Magnitude>12 then
            m.message="Aproxime-se de um minério ou ative a busca automática"; return
        end
        if window:GetFlag("mush.mine.move") then approach(c,h,root,target); sleep(ctx,.3)
        else local pos=target:GetPivot().Position; root.CFrame=CFrame.lookAt(root.Position,Vector3.new(pos.X,root.Position.Y,pos.Z)) end
        if tool.Parent~=c then h:EquipTool(tool); sleep(ctx,.25) end
        local control=nativeController(tool)
        assert(control,"O controlador nativo da picareta não ficou disponível")
        m.controller=control
        if value(control.active) or value(control.result) then m.message="Aguardando terminar a mineração anterior"; return end
        local session={tool=tool,controller=control,character=c,humanoid=h,target=target,lastSwing=-math.huge}
        m.session=session
        local initial=size(m.ores); local clicked=setmetatable({},{__mode="k"}); local nextClick=0
        local deadline=os.clock()+45; local wasActive=false; local activeEnded; local decision
        local ok,err=pcall(function()
            while os.clock()<deadline do
                ctx:ThrowIfCancelled()
                if player.Character~=c or h.Health<=0 or tool.Parent~=c or hub:InBoardGame() then return end
                if value(control.result) then
                    m.message="Guardando minério"
                    if not decision then local button=resultButton("Catch")
                        if button then ctx:ThrowIfCancelled(); firesignal(button.Activated); decision=os.clock() end
                    end
                elseif value(control.active) then
                    wasActive=true; activeEnded=nil; m.message="Minerando • clicando nos círculos"
                    local button=circle()
                    if button and not clicked[button] and os.clock()>=nextClick then
                        ctx:ThrowIfCancelled(); clicked[button]=true; firesignal(button.Activated)
                        m.clicks=m.clicks+1; nextClick=os.clock()+.07
                    end
                elseif decision then
                    if size(m.ores)>initial then session.completed=true; m.message="Minério confirmado; preparando próximo ciclo"; return end
                    assert(os.clock()-decision<5,"O servidor não confirmou que o minério foi guardado")
                elseif wasActive then
                    activeEnded=activeEnded or os.clock()
                    if os.clock()-activeEnded>.75 then m.message="Minigame terminou sem coleta; tentando novamente"; return end
                else
                    if not target.Parent then m.target=nil; m.message="Minério esgotado; buscando outro"; return end
                    m.message="Golpeando minério "..target.Name
                    if os.clock()-session.lastSwing>=1.2 then
                        ctx:ThrowIfCancelled(); tool:Activate(); session.lastSwing=os.clock(); m.swings=m.swings+1
                    end
                end
                sleep(ctx,.035)
            end
            m.blocked[target]=os.clock()+10; m.target=nil
            m.message="Minério sem resposta: buscando outro alvo"
        end)
        cleanSession(session,ctx:IsCancelled() or not ok or not session.completed)
        if not ok and not ctx:IsCancelled() then error(err) end
    end

    local tab=window:CreateTab({Title="Mineração",Icon="pickaxe",Columns=1})
    local mine=tab:CreateSection({Title="Auto mineração",Icon="pickaxe"})
    local toggle=mine:AddToggle({Id="mush.mine.enabled",Title="Ativar Auto Mineração",Icon="pickaxe",Default=false,
        Tooltip="Equipa a Pickaxe, encontra minério, golpeia, clica nos círculos reais e guarda o resultado. Ao ativar, pausa Auto Fish."})
    mine:AddToggle({Id="mush.mine.move",Title="Buscar e ir até minérios",Icon="map",Default=true,
        Tooltip="Reposiciona o personagem junto ao minério carregado mais próximo e o mantém como alvo até esgotar. Desligado, minere perto do personagem."})
    mine:AddSlider({Id="mush.mine.interval",Title="Pausa entre ciclos",Icon="clock",Min=.3,Max=5,Step=.1,Default=.5,Suffix=" s"})
    local label=mine:AddLabel({Id="mush.mine.status",Title="Estado da mineração",Icon="info",Default=m.message})
    mine:AddLabel({Id="mush.mine.instructions",Title="Como usar",Icon="info",
        Default="Tenha a Pickaxe na mochila e fique na região das minas. Ative Auto Mineração.\n"
            .."O minigame clica nos círculos nativos e guarda os minérios. O Miner cuida das vendas e reparações.\n"
            .."Só uma atividade de coleta roda por vez. Desligar durante o minigame aguarda sua liberação nativa (até cerca de 6s)."})
    local service=tab:CreateSection({Title="Venda e reparação no Miner",Icon="tools"})
    service:AddToggle({Id="mush.mine.sell",Title="Vender minérios quando a mochila encher",Icon="coins",Default=true,
        Tooltip="Visita o Miner, vende os minérios desbloqueados e volta ao ponto de mineração. Não vende peixes nem converte moedas."})
    service:AddToggle({Id="mush.mine.repair",Title="Reparar a picareta automaticamente",Icon="wrench",Default=true,
        Tooltip="Repara a picareta equipada com prata pelo fluxo do Miner. Só confirma após MiningDataChanged mostrar aumento de durabilidade. A Wooden Pickaxe não gasta durabilidade."})
    service:AddSlider({Id="mush.mine.threshold",Title="Reparar abaixo de",Icon="sliders",Min=10,Max=95,Step=5,Default=30,Suffix="%"})
    local pickCard=service:AddStatCard({Id="mush.mine.pickaxe",Title="Picareta equipada",Icon="pickaxe",Value="—"})
    local durability=service:AddStatCard({Id="mush.mine.durability",Title="Durabilidade",Icon="shield",Value=0,Format="Percent"})
    local bag=service:AddStatCard({Id="mush.mine.bag",Title="Mochila",Icon="backpack",Value="—"})
    service:AddButton({Id="mush.mine.sell-now",Title="Vender minérios agora",Text="VENDER",Icon="coins",
        Group="mush.activities",Policy="Queue",Cancelable=true,Callback=function(_,ctx)
            local ok,msg=m:Maintain(ctx,true,false); m.message=msg; return ok,msg
        end})
    service:AddButton({Id="mush.mine.repair-now",Title="Reparar picareta agora",Text="REPARAR",Icon="wrench",
        Group="mush.activities",Policy="Queue",Cancelable=true,Callback=function(_,ctx)
            local ok,msg=m:Maintain(ctx,false,true); m.message=msg; return ok,msg
        end})
    local stats=tab:CreateSection({Title="Resultados confirmados",Icon="grid"})
    local collected=stats:AddStatCard({Id="mush.mine.collected",Title="Minérios guardados",Icon="success",Value=0})
    local sales=stats:AddStatCard({Id="mush.mine.sales",Title="Minérios vendidos",Icon="coins",Value=0})
    local repairs=stats:AddStatCard({Id="mush.mine.repairs",Title="Reparações confirmadas",Icon="wrench",Value=0})
    local details=stats:AddLabel({Id="mush.mine.details",Title="Esta execução",Icon="info",Default="—"})
    local job=window:CreateTask({Id="mush.mining.cycle",Interval=.5,Group="mush.activities",Policy="Queue",Start=false,OnError="Stop",Callback=cycle})
    m.job=job; toggle:BindTask(job,{Initial="Control",OnStop="TurnOff"})
    window:Manage(window:GetFlagState("mush.mine.interval"):Subscribe(function(v)job:SetInterval(v)end,true),"Disconnect")
    window:Manage(window:GetFlagState("mush.mine.enabled"):Subscribe(function(enabled)
        if enabled then window:SetFlag("mush.auto.enabled",false)
        elseif not m:IsBusy() then m.message="Auto mineração desligado" end
    end),"Disconnect")
    window:Manage(window:GetFlagState("mush.auto.enabled"):Subscribe(function(enabled)
        if enabled then window:SetFlag("mush.mine.enabled",false) end
    end),"Disconnect")
    window:CreateTask({Id="mush.mining.telemetry",Interval=.5,Start=true,OnError="Continue",Callback=function(ctx)
        ctx:ThrowIfCancelled(); local data=read(); local status=job:GetStatus()
        local message=status.LastError and "Erro: "..tostring(status.LastError) or status.Status=="Cancelling" and "Cancelando e aguardando o minigame nativo terminar" or m.message
        if not status.Active and not m:IsBusy() and not status.LastError then message="Auto mineração desligado" end
        label:SetText(message); collected:SetValue(m.collected); sales:SetValue(m.sold); repairs:SetValue(m.repairs)
        local pick=data.pickaxe
        pickCard:SetValue(pick and pick.name or "Aguardando dados")
        durability:SetValue(pick and pick.current/pick.max*100 or 0)
        durability:SetSubtitle(pick and (pick.breakable and string.format("%.1f / %d",pick.current,pick.max) or "Não se desgasta") or "—")
        bag:SetValue(string.format("%d / %d • %d minérios",data.count,data.capacity,data.ores))
        details:SetText(string.format("%d golpes • %d círculos clicados\nPrata recebida: %.1f • reparações: %.1f prata",m.swings,m.clicks,m.earned,m.spent))
    end})
    function m:GetSnapshot()
        return {status=self.message,collected=self.collected,clicks=self.clicks,swings=self.swings,sales=self.sales,sold=self.sold,
            repairs=self.repairs,earned=self.earned,spent=self.spent,busy=self:IsBusy(),data=read(),task=job:GetStatus()}
    end
    window:OnDestroy(function()m.alive=false end)
    return m
end

end)()
local makePoolPlanner=(function()
-- Planejamento em cópias das bolas, com SnookerPhysics nativo e orçamento de tempo.
return function(physics, config)
    local P={}
    local V=Vector3.new
    local abs,min,max,sqrt=math.abs,math.min,math.max,math.sqrt
    local function distanceSegment(point,a,b)
        local d=b-a; local length=d:Dot(d)
        if length<1e-10 then return (point-a).Magnitude end
        local t=math.clamp((point-a):Dot(d)/length,0,1)
        return (point-(a+d*t)).Magnitude
    end
    local function clear(s,a,b,skip1,skip2)
        for _,ball in s.balls do
            if not ball.Pocketed and ball.Id~=skip1 and ball.Id~=skip2 and
                distanceSegment(ball.Pos,a,b)<s.frame.Diameter*.995 then return false end
        end
        return true
    end
    local function inside(s,p)
        local f=s.frame; local r=f.Diameter*.5
        return abs(p.X)<f.HalfLong-r and abs(p.Y)<f.HalfShort-r
    end
    local function allowed(s,id)
        if id==0 then return false end
        if s.cleared then return id==8 end
        if id==8 then return false end
        return s.group=="open" or (s.group=="solids" and id>=1 and id<=7) or (s.group=="stripes" and id>=9 and id<=15)
    end
    P.allowed=allowed
    function P.snapshot(model,diameter,team)
        local frame=physics.BuildFrame(model,diameter)
        if not frame then return nil,"Geometria da mesa não carregada" end
        local solids=model:GetAttribute("SolidsTeam")
        if type(solids)=="number" and type(team)~="number" then return nil,"Aguardando identificação do seu grupo" end
        local s={frame=frame,balls={},byId={},group=type(solids)~="number" and "open" or solids==team and "solids" or "stripes"}
        local folder=model:FindFirstChild("Balls")
        if not folder then return nil,"Bolas não carregadas" end
        for _,b in folder:GetChildren() do
            local id=b:GetAttribute("BallId")
            local root=b:IsA("Model") and (b.PrimaryPart or b:FindFirstChildWhichIsA("BasePart"))
            if type(id)=="number" and root then
                local ball={Id=id,Pos=physics.WorldToLocal(frame,root.Position),Pocketed=b:GetAttribute("Pocketed")==true}
                s.balls[#s.balls+1]=ball; s.byId[id]=ball
            end
        end
        if #s.balls~=16 or not s.byId[0] or not s.byId[8] then return nil,"Aguardando as 16 bolas da mesa" end
        table.sort(s.balls,function(a,b)return a.Id<b.Id end)
        s.cleared=s.group~="open"
        for _,b in s.balls do
            if not b.Pocketed and b.Id~=0 and b.Id~=8 and allowed({group=s.group,cleared=false},b.Id) then s.cleared=false end
        end
        s.pockets=physics.NewState(frame).Pockets
        return s
    end
    function P.key(s)
        local t={s.group,tostring(s.cleared)}
        for _,b in s.balls do
            t[#t+1]=b.Pocketed and tostring(b.Id).."p" or string.format("%d:%.4f:%.4f",b.Id,b.Pos.X,b.Pos.Y)
        end
        return table.concat(t,";")
    end
    local function geometric(s,white,ball,pocket)
        local delta=pocket-ball.Pos
        if delta.Magnitude<.001 then return end
        local outward=delta.Unit; local ghost=ball.Pos-outward*s.frame.Diameter
        local aim=ghost-white
        if aim.Magnitude<.001 or not inside(s,ghost) then return end
        local cosine=aim.Unit:Dot(outward)
        if cosine<.12 or not clear(s,white,ghost,0,ball.Id) or not clear(s,ball.Pos,pocket,0,ball.Id) then return end
        local estimate=sqrt(2*config.GetDecel()*(aim.Magnitude+delta.Magnitude/(cosine*cosine*.90)))/config.GetMaxImpulse()+.025
        local quality=cosine*cosine/(1+(aim.Magnitude+delta.Magnitude)/(s.frame.Diameter*24))
        return {heading=aim.Unit,power=math.clamp(estimate,.07,1),target=ball.Id,
            priority=500+quality*500,ghost=ghost,pocket=pocket,kind="Encaçapada direta",distance=aim.Magnitude}
    end
    local function candidates(s)
        local white=s.byId[0].Pos; local all={}; local seen={}
        local function add(c)
            local h=c.heading
            local key=string.format("%.4f:%.4f:%.3f",h.X,h.Y,c.power)
            if not seen[key] then seen[key]=true; all[#all+1]=c end
        end
        local nearestFallback
        for _,ball in s.balls do
            if ball.Pocketed or not allowed(s,ball.Id) then continue end
            local delta=ball.Pos-white
            if delta.Magnitude<.001 then continue end
            if clear(s,white,ball.Pos,0,ball.Id) then
                local base=sqrt(2*config.GetDecel()*(delta.Magnitude+s.frame.HalfLong))/config.GetMaxImpulse()
                for i,power in {math.clamp(base+.04,.12,.65),.48,.72,1} do
                    local c={heading=delta.Unit,power=power,target=ball.Id,priority=100-i*3-delta.Magnitude,
                        ghost=ball.Pos-delta.Unit*s.frame.Diameter,kind="Contato e defesa",distance=delta.Magnitude}
                    add(c)
                    if i==1 and (not nearestFallback or c.distance<nearestFallback.distance) then nearestFallback=c end
                end
            end
            for _,pocket in s.pockets do
                local c=geometric(s,white,ball,pocket)
                if c then
                    for i,factor in {1,.87,1.15} do
                        local variant=table.clone(c); variant.power=math.clamp(c.power*factor,.05,1)
                        variant.priority=c.priority-(i-1)*35; add(variant)
                    end
                end
            end
            -- Uma tabela da branca: alvo espelhado na linha real de colisão da borda.
            local f=s.frame; local r=f.Diameter/2
            for axis=1,2 do
                for _,sign in {-1,1} do
                    local bound=sign*(axis==1 and f.HalfLong-r or f.HalfShort-r)
                    local mirror=axis==1 and V(2*bound-ball.Pos.X,ball.Pos.Y,0) or V(ball.Pos.X,2*bound-ball.Pos.Y,0)
                    local d=mirror-white
                    local component=axis==1 and d.X or d.Y
                    if abs(component)<1e-5 then continue end
                    local t=(bound-(axis==1 and white.X or white.Y))/component
                    if t<=0 or t>=1 then continue end
                    local rail=white+d*t
                    if axis==1 and abs(rail.Y)>f.HalfShort-r*3 then continue end
                    if axis==2 and (abs(rail.X)>f.HalfLong-r*3 or abs(rail.X)<r*3) then continue end
                    if not clear(s,white,rail,0,nil) or not clear(s,rail,ball.Pos,0,ball.Id) then continue end
                    local power=math.clamp(sqrt(2*config.GetDecel()*(d.Magnitude+f.HalfLong))/config.GetMaxImpulse()+.07,.15,.85)
                    add({heading=d.Unit,power=power,target=ball.Id,priority=40-d.Magnitude,ghost=rail,kind="Defesa por tabela",distance=d.Magnitude})
                end
            end
        end
        table.sort(all,function(a,b)return a.priority>b.priority end)
        -- Testa uma defesa antes das tentativas de encaçapar, reservando uma alternativa válida.
        if nearestFallback then table.insert(all,1,table.clone(nearestFallback)) end
        return all
    end
    local function ease(s,balls,white,own)
        local copy={frame=s.frame,balls=balls}
        local best=0
        for _,b in balls do
            if b.Id==0 or b.Pocketed or (allowed(s,b.Id)~=own) then continue end
            if b.Id==8 and not s.cleared then continue end
            for _,pocket in s.pockets do
                local c=geometric(copy,white,b,pocket)
                if c then best=max(best,(c.priority-500)/500) end
            end
        end
        return best
    end
    local function evaluate(s,state,first,rail,potted,candidate)
        if not first or not allowed(s,first) then return nil,"Primeiro contato fora do grupo" end
        if state.ById[0].Pocketed then return nil,"Branca na caçapa" end
        if potted[8] and not s.cleared then return nil,"Bola 8 antecipada" end
        local own,enemy,solid,stripe=0,0,0,0
        for id in potted do
            if id>=1 and id<=7 then solid=solid+1 elseif id>=9 then stripe=stripe+1 end
            if id~=0 and id~=8 then if allowed(s,id) then own=own+1 else enemy=enemy+1 end end
        end
        if s.group=="open" then own,enemy=max(solid,stripe),min(solid,stripe) end
        if own==0 and not potted[8] and not rail then return nil,"Sem caçapa nem tabela após contato" end
        local score=own*1200-enemy*1000-candidate.power*15
        if potted[8] and s.cleared then score=score+100000 end
        local white=state.ById[0].Pos
        score=score+ease(s,state.Balls,white,true)*110
        if own==0 then score=score-ease(s,state.Balls,white,false)*160 end
        -- Afasta a branca das bocas e considera sua posição para a próxima tacada.
        local closest=math.huge
        for _,pocket in s.pockets do closest=min(closest,(white-pocket).Magnitude) end
        score=score+min(closest/s.frame.Diameter,5)*3
        local count=0; for _,b in s.balls do if not b.Pocketed and b.Id~=0 then count=count+1 end end
        if s.group=="open" and count>=14 then
            local spread=0
            for _,b in state.Balls do if b.Id~=0 and not b.Pocketed then spread=spread+(b.Pos-V(s.frame.Diameter*8,0,0)).Magnitude end end
            score=score+spread*1.5
        end
        return {score=score,first=first,ownPotted=own,enemyPotted=enemy,potted=potted,
            scratch=false,blackEarly=false,win=potted[8] and s.cleared or false,rail=rail}
    end
    function P.simulate(s,candidate,poll)
        local state=physics.NewState(s.frame)
        for _,b in s.balls do local ball=physics.AddBall(state,b.Id,b.Pos); ball.Pocketed=b.Pocketed end
        local worldHeading=s.frame.Long*candidate.heading.X+s.frame.Short*candidate.heading.Y
        physics.ApplyStrike(state,candidate.power,worldHeading)
        local first,rail=nil,false; local potted={}; local previous={}
        local dt=config.GetFixedDt(); local maxSteps=math.ceil(config.GetMaxSimTime()/dt)
        for step=1,maxSteps do
            if poll and step%32==0 then poll() end
            if physics.Settled(state) then
                local result,reason=evaluate(s,state,first,rail,potted,candidate)
                if result then result.duration=(step-1)*dt; result.state=state; result.heading=worldHeading; result.power=candidate.power
                    result.target=candidate.target; result.kind=result.ownPotted>0 and candidate.kind or "Contato e defesa"; result.ghost=candidate.ghost end
                return result,reason
            end
            local whiteBefore=state.ById[0].Pos
            for _,b in state.Balls do previous[b.Id]=b.Vel end
            local ev=physics.Step(state)
            for _,id in ev.Pocketed do potted[id]=true end
            if not first then
                local nearest=math.huge
                for _,b in state.Balls do
                    if b.Id~=0 and not s.byId[b.Id].Pocketed and (b.Vel.Magnitude>.001 or potted[b.Id]) then
                        local dist=(b.Pos-whiteBefore).Magnitude
                        if dist<nearest then nearest=dist; first=b.Id end
                    end
                end
            end
            if first then
                for _,b in state.Balls do
                    if b.Pocketed then continue end
                    local prev=previous[b.Id]
                    local xNear=abs(b.Pos.X)>=s.frame.HalfLong-state.Radius-abs(prev.X)*dt*1.5-s.frame.Diameter*.1
                    local yNear=abs(b.Pos.Y)>=s.frame.HalfShort-state.Radius-abs(prev.Y)*dt*1.5-s.frame.Diameter*.1
                    if (xNear and prev.X*b.Vel.X<0) or (yNear and prev.Y*b.Vel.Y<0) then rail=true end
                end
            end
        end
        return nil,"Simulação não estabilizou"
    end
    function P.search(s,options)
        options=options or {}; local start=os.clock(); local deadline=start+(options.seconds or 3)
        local slice=start; local tested,safe=0,0
        local function poll()
            if options.context then options.context:ThrowIfCancelled() end
            if options.cancelled and options.cancelled() then error("MUSH_POOL_STALE",0) end
            if os.clock()>=deadline then error("MUSH_POOL_TIME",0) end
            if os.clock()-slice>.004 then task.wait(); slice=os.clock() end
        end
        local list=candidates(s); local best
        local maxTests=options.samples or 40
        local baseLimit=min(#list,max(1,maxTests-4))
        local limit=min(#list+4,maxTests)
        local function try(candidate)
            poll()
            local result=P.simulate(s,candidate,poll); tested=tested+1
            if result then
                safe=safe+1
                if not best or result.score>best.score then best=result end
            end
            if options.progress then options.progress(tested,limit,best) end
        end
        local ok,err=pcall(function()
            for i=1,baseLimit do try(list[i]); if best and best.win then break end end
            if best and not best.win then
                local base=best
                local angle=math.atan2(base.heading:Dot(s.frame.Short),base.heading:Dot(s.frame.Long))
                local white=s.byId[0].Pos; local d=(base.ghost-white).Magnitude
                local step=math.atan2(s.frame.Diameter*.12,max(d,s.frame.Diameter))
                for _,offset in {-step,step} do
                    for _,factor in {.94,1.06} do
                        if tested>=maxTests then break end
                        try({heading=V(math.cos(angle+offset),math.sin(angle+offset),0),power=math.clamp(base.power*factor,.04,1),
                            target=base.target,kind="Mira refinada",ghost=base.ghost})
                    end
                end
            end
        end)
        if not ok and not tostring(err):find("MUSH_POOL_TIME",1,true) then error(err,0) end
        return best,{tested=tested,safe=safe,generated=#list,seconds=os.clock()-start,limited=not ok}
    end
    function P.place(s,maxLong)
        local f=s.frame; local d=f.Diameter; local left=-f.HalfLong+d; local right=min(f.HalfLong-d,maxLong-d*.5)
        if right<left then return nil end
        local function usable(p)
            if p.X<left or p.X>right or abs(p.Y)>f.HalfShort-d then return false end
            for _,b in s.balls do if b.Id~=0 and not b.Pocketed and (b.Pos-p).Magnitude<d*1.1 then return false end end
            for _,pocket in s.pockets do if (p-pocket).Magnitude<d*1.6 then return false end end
            return true
        end
        local best,bestScore
        for _,ball in s.balls do
            if ball.Pocketed or not allowed(s,ball.Id) then continue end
            for _,pocket in s.pockets do
                local delta=pocket-ball.Pos
                if delta.Magnitude<.001 then continue end
                for _,multiplier in {3,5,8} do
                    local pos=ball.Pos-delta.Unit*d*multiplier
                    if usable(pos) then
                        local c=geometric(s,pos,ball,pocket)
                        if c and (not bestScore or c.priority>bestScore) then best,bestScore=pos,c.priority end
                    end
                end
            end
        end
        if best then return physics.LocalToWorld(f,best) end
        local x=math.clamp(config.GetWhite().Long*d,left,right)
        for _,y in {0,f.HalfShort*.3,-f.HalfShort*.3,f.HalfShort*.6,-f.HalfShort*.6} do
            local pos=V(x,y,0); if usable(pos) then return physics.LocalToWorld(f,pos) end
        end
        for ix=0,6 do for iy=-3,3 do
            local pos=V(left+(right-left)*ix/6,iy*(f.HalfShort-d)/3,0)
            if usable(pos) then return physics.LocalToWorld(f,pos) end
        end end
        return nil
    end
    return P
end

end)()
local installPoolAuto=(function()
return function(window, Library, player, RS, proto, ups, pool, Planner)
    local client=require(RS.Client.Snooker)
    local physics=require(RS.Modules.SnookerPhysics)
    local config=require(RS.Configuration.Snooker)
    local events=require(RS.Modules.Events)
    local diameter=RS.Assets.Snooker.Ball:GetExtentsSize().X
    local ai={alive=true,message="Auto play de sinuca desligado",submitted=0,confirmed=0,potted=0,placements=0,retries=0}
    local watch=window:CreateScope()
    local tab=pool.tab
    local section=tab:CreateSection({Title="Auto play inteligente",Icon="crown"})
    local toggle=section:AddToggle({Id="mush.snooker.auto",Title="Jogar sinuca automaticamente",Icon="crown",Default=false,
        Tooltip="Na sua vez, simula direções e forças com SnookerPhysics. Busca encaçapadas e defesas; evita branca na caçapa, contato fora do grupo e bola 8 antecipada. Não garante vitória."})
    section:AddToggle({Id="mush.snooker.auto-place",Title="Posicionar a branca automaticamente",Icon="target",Default=true,
        Tooltip="Usa a confirmação nativa para posicionar a branca na saída e na bola na mão após faltas, respeitando limites e outras bolas."})
    section:AddToggle({Id="mush.snooker.auto-preview",Title="Mostrar a trajetória escolhida pela IA",Icon="eye",Default=true,
        Tooltip="Exibe a simulação da tacada escolhida e a mantém durante o movimento. Usa as opções de trajetórias e marcas desta aba."})
    section:AddSlider({Id="mush.snooker.auto-time",Title="Tempo de análise por tacada",Icon="clock",Min=.5,Max=8,Step=.5,Default=3,Suffix=" s",
        Tooltip="Orçamento máximo de busca. Também respeita o tempo restante da sua vez. Mais tempo permite comparar mais opções."})
    section:AddSlider({Id="mush.snooker.auto-samples",Title="Limite de opções simuladas",Icon="sliders",Min=12,Max=80,Step=4,Default=36,
        Tooltip="Compara tacadas diretas, forças diferentes, contatos defensivos e tabelas da branca. A busca para no limite de tempo."})
    local label=section:AddLabel({Id="mush.snooker.auto-status",Title="Estado do auto play",Icon="notification",Default=ai.message})
    local details=section:AddLabel({Id="mush.snooker.auto-analysis",Title="Última escolha",Icon="target",Default="Nenhuma tacada calculada"})
    local shots=section:AddStatCard({Id="mush.snooker.auto-shots",Title="Tacadas confirmadas",Icon="success",Value=0})
    local potted=section:AddStatCard({Id="mush.snooker.auto-potted",Title="Bolas-alvo encaçapadas",Icon="target",Value=0})
    section:AddLabel({Id="mush.snooker.auto-help",Title="Funcionamento",Icon="info",
        Default="Entre normalmente numa partida e ative o auto play. A IA espera sua vez e as bolas pararem.\n"
            .."Avalia direções, forças, capturas e posição da branca para a próxima tacada; usa a execução nativa do jogo.\n"
            .."A prévia manual pausa enquanto a IA está ligada. Ao desligar, uma tacada já enviada continua sendo resolvida pelo jogo."})

    local function busy(model)
        local context=pool:ReadContext()
        return context and context.model==model and context.busy or false
    end
    local function watchModel(model)
        if ai.model==model then return end
        watch:Clean(); ai.model=model; ai.pending=nil; ai.failedKey=nil; ai.retries=0
        watch:Add(model:GetAttributeChangedSignal("SnookerBusy"):Connect(function()
            local pending=ai.pending
            if pending and pending.model==model and model:GetAttribute("SnookerBusy")==true and not pending.ack then
                pending.ack=true; ai.confirmed=ai.confirmed+1
            end
        end))
        local balls=model:FindFirstChild("Balls")
        if balls then for _,ball in balls:GetChildren() do
            watch:Add(ball:GetAttributeChangedSignal("Pocketed"):Connect(function()
                local pending=ai.pending; local id=ball:GetAttribute("BallId")
                if pending and pending.model==model and id and not pending.before[id] and not pending.seen[id] and ball:GetAttribute("Pocketed")==true then
                    pending.seen[id]=true
                    if Planner.allowed(pending.snapshot,id) then ai.potted=ai.potted+1 end
                end
            end))
        end end
    end
    local function placement(context,snapshot)
        if ai.placementAt and os.clock()-ai.placementAt<1.5 then return false,"Aguardando confirmação da posição da branca" end
        for _,fn in ipairs(proto(client.PlaceWhite,11,true)) do
            local u=ups(fn)
            local white=u[3]
            if u[1]==false and u[2]==nil and typeof(white)=="Instance" and white.Parent==context.model:FindFirstChild("Balls")
                and type(u[5])=="table" and type(u[6])=="function" then
                local upper
                for _,resolve in ipairs(proto(client.PlaceWhite,9,true)) do
                    local r=ups(resolve)
                    if r[1]==u[5] and type(r[2])=="number" then upper=r[2]; break end
                end
                if not upper then return false,"Aguardando os limites nativos de posicionamento" end
                local pos=Planner.place(snapshot,upper)
                if not pos or not u[6](pos) then return false,"Nenhuma posição livre para a branca" end
                -- Finish desconecta a mira de posicionamento e chama a confirmação original.
                white:PivotTo(CFrame.new(pos+Vector3.new(0,diameter,0)))
                ai.placementAt=os.clock(); fn(); ai.placements=ai.placements+1
                return true,"Confirmando a posição da branca"
            end
        end
        return false,"Aguardando o posicionador nativo da branca"
    end
    local function validContext(c,model)
        return c and c.model==model and model.Parent and not c.placing and not c.busy and not c.holding and not c.pending
            and model:GetAttribute("ShooterId")==player.UserId
    end
    local job=window:CreateTask({Id="mush.snooker.auto-task",Interval=.2,Start=false,OnError="Stop",Callback=function(ctx)
        ctx:ThrowIfCancelled()
        local context=pool:ReadContext()
        if not context or not player.PlayerGui:FindFirstChild("Snooker") then
            ai.message="Entre numa partida de sinuca"; return
        end
        local model=context.model; watchModel(model)
        local pending=ai.pending
        if pending then
            if context.busy then ai.message="Tacada em movimento; aguardando as bolas pararem"; return end
            if pending.ack then ai.pending=nil; ai.message="Tacada resolvida; aguardando a vez"; return end
            if os.clock()-pending.at>5 then error("O servidor não confirmou a tacada. Auto play pausado para evitar envios duplicados.") end
            ai.message="Aguardando confirmação da tacada pelo servidor"; return
        end
        if model:GetAttribute("ShooterId")~=player.UserId then ai.message="Aguardando a vez do adversário"; return end
        if context.busy then ai.message="Aguardando as bolas pararem"; return end
        if context.holding or context.pending then ai.message="Aguardando terminar sua tacada manual"; return end
        local snapshot,reason=Planner.snapshot(model,diameter,context.team)
        if not snapshot then ai.message=reason; return end
        if context.placing then
            if not window:GetFlag("mush.snooker.auto-place") then ai.message="Posicione a branca para a IA começar"; return end
            ctx:ThrowIfCancelled()
            local _,message=placement(context,snapshot); ai.message=message; return
        end
        ai.placementAt=nil
        if snapshot.byId[0].Pocketed then ai.message="Aguardando a branca voltar à mesa"; return end
        local signature=Planner.key(snapshot)
        if ai.failedKey==signature and ai.retries>=2 then ai.message="Não encontrei tacada sem falta prevista. Aumente o tempo de análise ou jogue esta vez manualmente."; return end
        local seconds=window:GetFlag("mush.snooker.auto-time") or 3
        local ends=model:GetAttribute("TurnEnds")
        if type(ends)=="number" then seconds=math.min(seconds,ends-workspace:GetServerTimeNow()-.65) end
        if seconds<.2 then ai.message="Tempo da vez terminando; aguardando atualização do jogo"; return end
        ai.message="Comparando tacadas e forças..."; pool:Clear()
        local function stale()
            if not ai.alive then return true end
            local c=pool:ReadContext()
            if not validContext(c,model) then return true end
            local s=Planner.snapshot(model,diameter,c.team)
            return not s or Planner.key(s)~=signature
        end
        local ok,best,stats=pcall(Planner.search,snapshot,{context=ctx,seconds=seconds,samples=window:GetFlag("mush.snooker.auto-samples"),
            cancelled=stale,progress=function(n,total,result)
                ai.message=string.format("Analisando %d/%d opções%s",n,total,result and " • alternativa sem falta encontrada" or "")
            end})
        if not ok then
            if ctx:IsCancelled() or stale() or tostring(best):find("MUSH_POOL_STALE",1,true) then return end
            error(best)
        end
        ctx:ThrowIfCancelled()
        if stale() then return end
        ai.analysis={tested=stats.tested,safe=stats.safe,seconds=stats.seconds,power=best and best.power,target=best and best.target,
            first=best and best.first,ownPotted=best and best.ownPotted,enemyPotted=best and best.enemyPotted,kind=best and best.kind,win=best and best.win}
        if not best then
            ai.retries=ai.failedKey==signature and ai.retries+1 or 1; ai.failedKey=signature
            ai.message="Nenhuma opção sem falta prevista nesta busca; ampliando a comparação"
            details:SetText(string.format("%d opções completas em %.2fs; nenhuma passou pelo filtro de segurança",stats.tested,stats.seconds))
            return
        end
        ai.failedKey=nil; ai.retries=0
        local pots={}; for id in best.potted do if id~=0 then pots[#pots+1]=id end end; table.sort(pots)
        local names={}; for _,id in pots do names[#names+1]=tostring(id) end
        details:SetText(string.format("%s • primeiro contato: bola %d • força %.1f%%\nCaçapas previstas: %s • %d opções em %.2fs%s",
            best.kind,best.first,best.power*100,#names>0 and table.concat(names,", ") or "nenhuma",stats.tested,stats.seconds,
            best.win and " • bola 8 no momento correto" or ""))
        if window:GetFlag("mush.snooker.auto-preview") then pool:ShowAutoShot(ctx,best.power,best.heading) end
        ctx:ThrowIfCancelled()
        if stale() then return end
        local live=pool:ReadContext()
        local before={}; for _,b in snapshot.balls do if b.Pocketed then before[b.Id]=true end end
        ai.pending={model=model,at=os.clock(),snapshot=snapshot,before=before,seen={}}
        -- Callback original: Blink.Snooker.Strike + RunShot(..., Reporting=true).
        -- O próprio jogo simula a tacada e envia seu resultado real.
        local sent,sendError=pcall(live.shoot,best.power,best.heading)
        if not sent then ai.pending=nil; error(sendError) end
        ai.submitted=ai.submitted+1; ai.message="Tacada enviada pelo controlador nativo"
    end})
    ai.job=job; toggle:BindTask(job,{Initial="Control",OnStop="TurnOff"})
    window:Manage(window:GetFlagState("mush.snooker.auto"):Subscribe(function(enabled)
        ai.failedKey=nil; ai.retries=0
        if not enabled then ai.message="Auto play de sinuca desligado"; pool:Clear() end
    end),"Disconnect")
    window:Manage(events:Bind("SnookerGameOver",function(model)
        if ai.model==model then ai.pending=nil; ai.message="Partida de sinuca encerrada"; pool:Clear() end
    end),"Disconnect")
    window:CreateTask({Id="mush.snooker.auto-telemetry",Interval=.25,Start=true,OnError="Continue",Callback=function(ctx)
        ctx:ThrowIfCancelled(); local s=job:GetStatus()
        label:SetText(s.LastError and "Erro: "..tostring(s.LastError) or ai.message)
        shots:SetValue(ai.confirmed); potted:SetValue(ai.potted)
        shots:SetSubtitle(string.format("%d envios • confirmação por SnookerBusy do servidor",ai.submitted))
    end})
    function ai:GetSnapshot()
        return {status=self.message,submitted=self.submitted,confirmed=self.confirmed,potted=self.potted,
            placements=self.placements,pending=self.pending~=nil,analysis=self.analysis,job=job:GetStatus()}
    end
    window:OnDestroy(function()ai.alive=false end)
    return ai
end

end)()
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
    pool.tab = tab
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
            if window:GetFlag("mush.snooker.auto") then return end
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
    function pool:ReadContext()
        if not self.callback then snapshotNative() end
        local fn = self.callback
        if not fn then return nil end
        local u = ups(fn)
        if typeof(u[3]) ~= "Instance" or not u[3].Parent or typeof(u[28]) ~= "Instance" or not u[28].Parent then
            self.callback = nil; self.scanAt = 0; return nil
        end
        if type(u[13]) ~= "function" or ups(u[13])[2] ~= u[3] then return nil end
        local team = ups(client.Cue)[7]
        if type(team) ~= "number" then
            if u[3]:GetAttribute("Team1Id") == player.UserId then team = 1
            elseif u[3]:GetAttribute("Team2Id") == player.UserId then team = 2 end
        end
        return {model=u[3], placing=u[1].Placing==true, busy=u[2][u[3]]~=nil or u[3]:GetAttribute("SnookerBusy")==true,
            holding=u[8]==true, pending=u[12]~=nil, shoot=u[13], team=team}
    end
    function pool:ShowAutoShot(ctx, power, heading)
        local context = self:ReadContext()
        if not context then return end
        local result = predict(ctx, {model=context.model, power=power, heading=heading, held=true})
        ctx:ThrowIfCancelled()
        result.lockedShot = true
        self.result = result
        draw(result)
        self.message = "Trajetória escolhida pela IA"
        status:SetText(self.message)
    end
    function pool:GetSnapshot()
        local r = self.result
        return {enabled = job:GetStatus().Requested, status = self.message, power = r and r.power,
            firstBall = r and r.first, seconds = r and r.time, moved = r and r.moved, collisions = r and r.collisions,
            auto = self.auto and self.auto:GetSnapshot()}
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
        return {count = #fishes + #ores + #lagan, fishCount = #fishes, oreCount = #ores, laganCount = #lagan,
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

    local RAW = "https://raw.githubusercontent.com/ManoGustavo0/RetroBox/main/dist/bootstrap/v2.lua"
    assert(type(loadstring) == "function", "RetroBox precisa de loadstring no executor.")
    local loaded, Library = pcall(function()
        local source = game:HttpGet(RAW)
        assert(type(source) == "string" and #source > 0, "Bootstrap vazio.")
        local chunk, compileError = loadstring(source)
        assert(chunk, compileError)
        return chunk({Channel = "stable"})
    end)
    assert(loaded, "Falha ao carregar RetroBox: " .. tostring(Library))
    assert(type(Library) == "table" and Library.APIVersion == 2 and type(Library.CreateWindow) == "function",
        "O bootstrap não retornou uma RetroBox compatível com a API 2.")

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
        Title = "MushYO Hub", Subtitle = "MushYO Hub · pesca, mineração, sinuca e xadrez",
        Icon = "target", Theme = "Retro98", Locale = "pt-BR",
        Settings = true, ShowProfile = true, Launcher = true, LauncherText = "UI",
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
    if typeof(window.Launcher) == "Instance" then window.Launcher.AutoLocalize = false end
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
    function hub:InBoardGame()
        return self:InSnooker() or (self.chess and self.chess:IsPlaying()) or false
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
        if hub.mining and (window:GetFlag("mush.mine.enabled") or hub.mining:IsBusy()) then
            hub.message = "Pesca pausada durante a mineração"
            return {Outcome = "Mining"}
        end
        if hub:InBoardGame() then
            hub.message = "Pesca suspensa durante o minigame de mesa"
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
            if hub:InBoardGame() then hub.message = "Pesca suspensa durante o minigame de mesa"; return {Outcome = "PlayingSnooker"} end
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
        Group = "mush.activities", Policy = "Queue", Start = false, OnError = "Stop", Callback = fishingCycle})
    hub.job = job
    function hub:Stop()
        window:SetFlags({["mush.auto.enabled"] = false, ["mush.sell.enabled"] = false,
            ["mush.repair.enabled"] = false, ["mush.snooker.enabled"] = false,
            ["mush.chess.preview"] = false, ["mush.chess.auto"] = false,
            ["mush.mine.enabled"] = false, ["mush.snooker.auto"] = false})
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
            maintenance = maintenance.status, snooker = self.snooker and self.snooker:GetSnapshot(),
            chess = self.chess and self.chess:GetSnapshot(), mining = self.mining and self.mining:GetSnapshot()}
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
        Tooltip = "Desliga pesca, mineração, venda, reparação, sinuca e xadrez; retorna ao ponto original se estiver visitando o NPC.",
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
        Group = "mush.activities", Policy = "Queue", Start = false, OnError = "Continue", Callback = function(ctx)
            ctx:ThrowIfCancelled()
            if hub:InBoardGame() then return {Outcome = "PlayingSnooker"} end
            if hub.mining and (window:GetFlag("mush.mine.enabled") or hub.mining:IsBusy()) then
                return {Outcome = "Mining"}
            end
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
    local poolPlanner = makePoolPlanner(require(RS.Modules.SnookerPhysics), require(RS.Configuration.Snooker))
    hub.snooker.auto = installPoolAuto(window, Library, player, RS, proto, upvalues, hub.snooker, poolPlanner)
    hub.chess = installChess(window, Library, player, RS, ChessEngine)
    hub.mining = installMining(hub, window, Library, player, RS, RF, events, upvalues)
    window:Notify({Title = "MushYO Hub", Icon = "target", Kind = "success", Duration = 6,
        Content = "Pronto. Pesca, Mineração, Sinuca e Xadrez disponíveis. Auto play inteligente na aba Sinuca."})
    print("[MushyoHub] pronto · RetroBox API 2 · pesca, mineração, manutenção, sinuca e xadrez")
end

task.defer(function()
    local ok, err = xpcall(main, function(message) return debug.traceback(tostring(message), 2) end)
    if not ok then
        if created then pcall(function() created:Destroy() end) end
        warn("MushYO Hub: " .. tostring(err))
    end
end)
