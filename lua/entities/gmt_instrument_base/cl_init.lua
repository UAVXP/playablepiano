include("shared.lua")

ENT.DEBUG = false

ENT.KeysDown = {}
ENT.KeysWasDown = {}

ENT.AllowAdvancedMode = false
ENT.AdvancedMode = false
ENT.ShiftMode = false

ENT.PageTurnSound = Sound( "GModTower/inventory/move_paper.wav" )
surface.CreateFont( "InstrumentKeyLabel", {
	size = 22, weight = 400, antialias = true, font = "Impact"
} )
surface.CreateFont( "InstrumentNotice", {
	size = 30, weight = 400, antialias = true, font = "Impact"
} )

// Load the MIDI module if it exists
if ( file.Exists("lua/bin/gmcl_midi_win32.dll", "MOD") ||
	 file.Exists("lua/bin/gmcl_midi_linux.dll", "MOD") ||
	 file.Exists("lua/bin/gmcl_midi_osx.dll", "MOD") ) then
	 	require("midi")
end

// For drawing purposes
// Override by adding MatWidth/MatHeight to key data
ENT.DefaultMatWidth = 128
ENT.DefaultMatHeight = 128
// Override by adding TextX/TextY to key data
ENT.DefaultTextX = 5
ENT.DefaultTextY = 10
ENT.DefaultTextColor = Color( 150, 150, 150, 255 )
ENT.DefaultTextColorActive = Color( 80, 80, 80, 255 )
ENT.DefaultTextInfoColor = Color( 120, 120, 120, 150 )

ENT.MaterialDir	= ""
ENT.KeyMaterials = {}

ENT.MainHUD = {
	Material = nil,
	X = 0,
	Y = 0,
	TextureWidth = 128,
	TextureHeight = 128,
	Width = 128,
	Height = 128,
}

ENT.AdvMainHUD = {
	Material = nil,
	X = 0,
	Y = 0,
	TextureWidth = 128,
	TextureHeight = 128,
	Width = 128,
	Height = 128,
}

ENT.BrowserHUD = {
	URL = "http://www.gmtower.org/apps/instruments/piano.php",
	Show = true, // display the sheet music?
	X = 0,
	Y = 0,
	Width = 1024,
	Height = 768,
}

local playablepiano_midi_port = CreateClientConVar("playablepiano_midi_port","0",true)
concommand.Add("playablepiano_midi_ports",function()
	local ports = midi.GetPorts()
	
	if not next(ports) then return end
	
	local port = ports[playablepiano_midi_port:GetInt()] or next(ports)
	
	for k,v in next,midi.GetPorts() do
		MsgN(k==port and "> " or "  ",k,"=",v)
	end
end)

concommand.Add("playablepiano_midi_load",function()
	require("midi")
end)

local playablepiano_midi_hear = CreateClientConVar("playablepiano_midi_hear","0",true)
hook.Add( "MIDI", "gmt_instrument_base", function( time, command, note, velocity )
	local instrument = LocalPlayer()
	instrument = instrument and instrument:IsValid()
	instrument = instrument.Instrument 
	instrument = instrument and instrument:IsValid()
	
    // Zero velocity NOTE_ON substitutes NOTE_OFF
    if !midi || midi.GetCommandName( command ) != "NOTE_ON" || velocity == 0 || !instrument.MIDIKeys || !instrument.MIDIKeys[note] then return end
	
	if not instrument.OnRegisteredKeyPlayed then return end
	
    instrument:OnRegisteredKeyPlayed( instrument.MIDIKeys[note].Sound, not playablepiano_midi_hear:GetBool() )
end)

local g_port
function ENT:OpenMIDI()
	
	if not midi then return end
	if midi.IsOpened() then return end
	local ports = midi.GetPorts()
	
	if not next(ports) then return end
	
	local port = ports[playablepiano_midi_port:GetInt()] or next(ports)
	
	midi.Open( port )
	
	g_port = port
end

local function CloseMIDI()
	
	if not midi then return end
	if not midi.IsOpened() then return end
	local ports = midi.GetPorts()
	
	if not next(ports) then return end
	if not g_port or not ports[g_port] then return end
	local port = g_port
	g_port = nil
	midi.Close( port )
end

function ENT:Initialize()

	self:PrecacheMaterials()
	
end

function ENT:Think()

	if !IsValid( LocalPlayer().Instrument ) || LocalPlayer().Instrument != self then return end

	if self.DelayKey && self.DelayKey > CurTime() then return end

	// Update last pressed
	for keylast, keyData in pairs( self.KeysDown ) do
		self.KeysWasDown[ keylast ] = self.KeysDown[ keylast ]
	end

	// Get keys
	for key, keyData in pairs( self.Keys ) do

		// Update key status
		self.KeysDown[ key ] = input.IsKeyDown( key )

		// Check for note keys
		if self:IsKeyTriggered( key ) then

			if self.ShiftMode && keyData.Shift then
				self:OnRegisteredKeyPlayed( keyData.Shift.Sound )
			elseif !self.ShiftMode then
				self:OnRegisteredKeyPlayed( keyData.Sound )
			end

		end

	end

	// Get control keys
	for key, keyData in pairs( self.ControlKeys ) do

		// Update key status
		self.KeysDown[ key ] = input.IsKeyDown( key )

		// Check for control keys
		if self:IsKeyTriggered( key ) then
			keyData( self, true )
		end

		// was a control key released?
		if self:IsKeyReleased( key ) then
			keyData( self, false )
		end

	end

	// Send da keys to everyone
	//self:SendKeys()

end



function ENT:IsKeyTriggered( key )
	return self.KeysDown[ key ] && !self.KeysWasDown[ key ]
end

function ENT:IsKeyReleased( key )
	return self.KeysWasDown[ key ] && !self.KeysDown[ key ]
end

function ENT:OnRegisteredKeyPlayed( key, suppressSound )

	if ( !suppressSound ) then
		// Play on the client first
		local sound = self:GetSound( key )

		self:EmitSound( sound, 100 )
	end

	// Network it
	net.Start( "InstrumentNetwork" )

		net.WriteEntity( self )
		net.WriteInt( INSTNET_PLAY, 3 )
		net.WriteString( key )

	net.SendToServer()

	// Add the notes (limit to max notes)
	/*if #self.KeysToSend < self.MaxKeys then

		if !table.HasValue( self.KeysToSend, key ) then // only different notes, please
			table.insert( self.KeysToSend, key )
		end

	end*/

end

// Network it up, yo
function ENT:SendKeys()

	if !self.KeysToSend then return end

	// Send the queue of notes to everyone

	// Play on the client first
	for _, key in ipairs( self.KeysToSend ) do

		local sound = self:GetSound( key )

		if sound then
			self:EmitSound( sound, 100 )
		end

	end

	// Clear queue
	self.KeysToSend = nil

end

function ENT:DrawKey( mainX, mainY, key, keyData, bShiftMode )

	if keyData.Material then
		if ( self.ShiftMode && bShiftMode && input.IsKeyDown( key ) ) ||
		   ( !self.ShiftMode && !bShiftMode && input.IsKeyDown( key ) ) then

			surface.SetTexture( self.KeyMaterialIDs[ keyData.Material ] )
			surface.DrawTexturedRect( mainX + keyData.X, mainY + keyData.Y,
									  self.DefaultMatWidth, self.DefaultMatHeight )
		end

	end

	// Draw keys
	if keyData.Label then

		local offsetX = self.DefaultTextX
		local offsetY = self.DefaultTextY
		local color = self.DefaultTextColor

		if ( self.ShiftMode && bShiftMode && input.IsKeyDown( key ) ) ||
		   ( !self.ShiftMode && !bShiftMode && input.IsKeyDown( key ) ) then

			color = self.DefaultTextColorActive
			if keyData.AColor then color = keyData.AColor end
		else
			if keyData.Color then color = keyData.Color end
		end

		// Override positions, if needed
		if keyData.TextX then offsetX = keyData.TextX end
		if keyData.TextY then offsetY = keyData.TextY end

		draw.DrawText( keyData.Label, "InstrumentKeyLabel",
						mainX + keyData.X + offsetX,
						mainY + keyData.Y + offsetY,
						color, TEXT_ALIGN_CENTER )
	end
end

function ENT:DrawHUD()

	surface.SetDrawColor( 255, 255, 255, 255 )

	local mainX, mainY, mainWidth, mainHeight

	// Draw main
	if self.MainHUD.Material && !self.AdvancedMode then

		mainX, mainY, mainWidth, mainHeight = self.MainHUD.X, self.MainHUD.Y, self.MainHUD.Width, self.MainHUD.Height

		surface.SetTexture( self.MainHUD.MatID )
		surface.DrawTexturedRect( mainX, mainY, self.MainHUD.TextureWidth, self.MainHUD.TextureHeight )

	end

	// Advanced main
	if self.AdvMainHUD.Material && self.AdvancedMode then

		mainX, mainY, mainWidth, mainHeight = self.AdvMainHUD.X, self.AdvMainHUD.Y, self.AdvMainHUD.Width, self.AdvMainHUD.Height

		surface.SetTexture( self.AdvMainHUD.MatID )
		surface.DrawTexturedRect( mainX, mainY, self.AdvMainHUD.TextureWidth, self.AdvMainHUD.TextureHeight )

	end

	// Draw keys (over top of main)
	for key, keyData in pairs( self.Keys ) do

		self:DrawKey( mainX, mainY, key, keyData, false )

		if keyData.Shift then
			self:DrawKey( mainX, mainY, key, keyData.Shift, true )
		end
	end

	// Sheet music help
	if !ValidPanel( self.Browser ) && self.BrowserHUD.Show then

		draw.DrawText( "SPACE FOR SHEET MUSIC", "InstrumentKeyLabel",
						mainX + ( mainWidth / 2 ), mainY + 60,
						self.DefaultTextInfoColor, TEXT_ALIGN_CENTER )

	end

	// Advanced mode
	if self.AllowAdvancedMode && !self.AdvancedMode then

		draw.DrawText( "CONTROL FOR ADVANCED MODE", "InstrumentKeyLabel",
						mainX + ( mainWidth / 2 ), mainY + mainHeight + 30,
						self.DefaultTextInfoColor, TEXT_ALIGN_CENTER )

	elseif self.AllowAdvancedMode && self.AdvancedMode then

		draw.DrawText( "CONTROL FOR BASIC MODE", "InstrumentKeyLabel",
						mainX + ( mainWidth / 2 ), mainY + mainHeight + 30,
						self.DefaultTextInfoColor, TEXT_ALIGN_CENTER )
	end

end

// This is so I don't have to do GetTextureID in the table EACH TIME, ugh
function ENT:PrecacheMaterials()

	if !self.Keys then return end

	self.KeyMaterialIDs = {}

	for name, keyMaterial in pairs( self.KeyMaterials ) do
		if type( keyMaterial ) == "string" then // TODO: what the fuck, this table is randomly created
			self.KeyMaterialIDs[name] = surface.GetTextureID( keyMaterial )
		end
	end

	if self.MainHUD.Material then
		self.MainHUD.MatID = surface.GetTextureID( self.MainHUD.Material )
	end

	if self.AdvMainHUD.Material then
		self.AdvMainHUD.MatID = surface.GetTextureID( self.AdvMainHUD.Material )
	end

end

function ENT:OpenSheetMusic()

	if ValidPanel( self.Browser ) || !self.BrowserHUD.Show then return end

	self.Browser = vgui.Create( "HTML" )
	self.Browser:SetVisible( false )

	local width = self.BrowserHUD.Width

	if self.BrowserHUD.AdvWidth && self.AdvancedMode then
		width = self.BrowserHUD.AdvWidth
	end

	local url = self.BrowserHUD.URL

	if self.AdvancedMode then
		url = self.BrowserHUD.URL .. "?&adv=1"
	end

	local x = self.BrowserHUD.X - ( width / 2 )

	self.Browser:OpenURL( url )

	// This is delayed because otherwise it won't load at all
	// for some silly reason...
	timer.Simple( .1, function()

		if ValidPanel( self.Browser ) then
			self.Browser:SetVisible( true )
			self.Browser:SetPos( x, self.BrowserHUD.Y )
			self.Browser:SetSize( width, self.BrowserHUD.Height )
		end

	end )

end

function ENT:CloseSheetMusic()

	if !ValidPanel( self.Browser ) then return end

	self.Browser:Remove()
	self.Browser = nil

end

function ENT:ToggleSheetMusic()

	if ValidPanel( self.Browser ) then
		self:CloseSheetMusic()
	else
		self:OpenSheetMusic()
	end

end

function ENT:SheetMusicForward()

	if !ValidPanel( self.Browser ) then return end

	self.Browser:Exec( "pageForward()" )
	self:EmitSound( self.PageTurnSound, 100, math.random( 120, 150 ) )

end

function ENT:SheetMusicBack()

	if !ValidPanel( self.Browser ) then return end

	self.Browser:Exec( "pageBack()" )
	self:EmitSound( self.PageTurnSound, 100, math.random( 100, 120 ) )

end


local g_dummy
function ENT:CaptureAllKeys(capture)
	if capture == true then
		
		if g_dummy and g_dummy:IsValid() then return end
		
		g_dummy = vgui.Create'EditablePanel'
		
		g_dummy:Dock(FILL)
		function g_dummy:OnMouseReleased()
			self:Remove()
			
			local instrument = LocalPlayer().Instrument 
			instrument = instrument and instrument:IsValid()
			
			RunConsoleCommand( "instrument_leave", instrument and instrument:EntIndex() )
			
		end
		g_dummy:MakePopup()
		
		return
	
	end
	
	g_dummy:Remove()
	
end

function ENT:OnRemove()

	self:CloseSheetMusic()

end

function ENT:Shutdown()

	self:CloseSheetMusic()
	
	self:CaptureAllKeys(false)
	
	self.AdvancedMode = false
	self.ShiftMode = false

	if self.OldKeys then
		self.Keys = self.OldKeys
		self.OldKeys = nil
	end

end

function ENT:ToggleAdvancedMode()
	self.AdvancedMode = !self.AdvancedMode

	if ValidPanel( self.Browser ) then
		self:CloseSheetMusic()
		self:OpenSheetMusic()
	end

end

function ENT:ToggleShiftMode()
	self.ShiftMode = !self.ShiftMode
end

function ENT:ShiftMod() end // Called when they press shift
function ENT:CtrlMod() end // Called when they press cntrl

hook.Add( "HUDPaint", "InstrumentPaint", function()

	if IsValid( LocalPlayer().Instrument ) then

		// HUD
		local inst = LocalPlayer().Instrument
		inst:DrawHUD()

		// Notice bar
		local name = inst.PrintName or "INSTRUMENT"
		name = string.upper( name )

		surface.SetDrawColor( 0, 0, 0, 180 )
		surface.DrawRect( 0, ScrH() - 60, ScrW(), 60 )

		draw.SimpleText( "PRESS TAB TO LEAVE THE " .. name, "InstrumentNotice", ScrW() / 2, ScrH() - 35, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1 )

	end

end )

net.Receive( "InstrumentNetwork", function( length, client )

	local ent = net.ReadEntity()
	local enum = net.ReadInt( 3 )

	// When the player uses it or leaves it
	if enum == INSTNET_USE then

		if IsValid( LocalPlayer().Instrument ) then
			LocalPlayer().Instrument:Shutdown()
		end
		
		CloseMIDI()
		
		LocalPlayer().Instrument = ent
		
		if ent and ent:IsValid() then
			ent.DelayKey = CurTime() + .1 // delay to the key a bit so they don't play on use key
			if ent:IsValid() then
				ent:CaptureAllKeys(true)
				ent:OpenMIDI()
			end
		end
		
	// Play the notes for everyone else
	elseif enum == INSTNET_HEAR then

		// Instrument doesn't exist
		if !IsValid( ent ) then return end

		if !ent.GetSound then return end
		
		// Don't play for the owner, they've already heard it!
		if IsValid( LocalPlayer().Instrument ) && LocalPlayer().Instrument == ent then
			return
		end

		// Gather note
		local key = net.ReadString()
		local sound = ent:GetSound( key )

		if sound then
			ent:EmitSound( sound, 80 )
		end

		// Gather notes
		/*local keys = net.ReadTable()

		for i=1, #keys do

			local key = keys[1]
			local sound = ent:GetSound( key )

			if sound then
				ent:EmitSound( sound, 80 )

				local eff = EffectData()
				eff:SetOrigin( ent:GetPos() + Vector(0, 0, 60) )
				eff:SetEntity( ent )

				util.Effect( "musicnotes", eff, true, true )
			end

		end*/

	end

end )
