--[[   _                                
	( )                               
   _| |   __   _ __   ___ ___     _ _ 
 /'_` | /'__`\( '__)/' _ ` _ `\ /'_` )
( (_| |(  ___/| |   | ( ) ( ) |( (_| |
`\__,_)`\____)(_)   (_) (_) (_)`\__,_) 

	DHTML

--]]

local JS_CallbackHack = [[(function(){
	var funcname = '%s';
	window[funcname] = function(){
		_gm[funcname].apply(_gm,arguments);
	}
})();]]

local ConsoleColors = {
	["default"] = Color(255,160,255),
	["text"] = Color(255,255,255),
	["error"] = Color(235,57,65),
	["warn"] = Color(227,181,23),
	["info"] = Color(100,173,229),
}

local FilterCVar = CreateClientConVar( "cinema_html_filter", 0, true, false )

local FILTER_ALL = 0
local FILTER_NONE = 1

PANEL = {}

AccessorFunc( PANEL, "m_bScrollbars", 			"Scrollbars", 		FORCE_BOOL )
AccessorFunc( PANEL, "m_bAllowLua", 			"AllowLua", 		FORCE_BOOL )

--[[---------------------------------------------------------

-----------------------------------------------------------]]
function PANEL:Init()

	self.History = {}
	self.CurrentPage = 0

	self.URL = ""

	self:SetScrollbars( true )
	self:SetAllowLua( true )

	self.JS = {}
	self.Callbacks = {}

	--
	-- Implement a console - because awesomium doesn't provide it for us anymore.
	--
	local console_funcs = {'log','error','debug','warn','info','gmod'}
	for _, func in pairs(console_funcs) do
		self:AddFunction( "console", func, function( param )
			self:ConsoleMessage( param, func )
		end )
	end
	
	self:AddFunction( "gmod", "getUrl", function( href, finished )
		self.URL = href

		if finished then
			self:OpeningURL( href ) -- browser controls suck
			self:FinishedURL( href )
		else
			self:OpeningURL( href )
		end
	end )

	self:AddFunction( "gmod", "detectFlash", function( detected )

		if !detected then

			warning.Add( "Adobe Flash was not detected, press F2 for help" )

			control.Add( KEY_F2, function( enabled, held )
				if enabled and !held then
					SetClipboardText( "http://get.adobe.com/flashplayer/otherversions/" )
					gui.OpenURL( "http://pixeltailgames.com/cinema/flash.php" )
				end
			end )

		end

	end )

	self:AddFunction( "window", "open", function()
		-- prevents popups from opening
	end)
	
	local oldFunc = self.OpenURL
	self.OpenURL = function( panel, url, history )

		if !history then
			-- Pop URLs from the stack
			while #panel.History != panel.CurrentPage do
				table.remove( panel.History )
			end
			table.insert( panel.History, url )
			panel.CurrentPage = panel.CurrentPage + 1
		end

		panel.URL = url
		oldFunc( panel, url )
	end

end

function PANEL:SetupCallbacks()

end

function PANEL:Think()

	if self:IsLoading() then

		-- Call started loading
		if not self._loading then

			-- Get the page URL
			self:RunJavascript("gmod.getUrl(window.location.href, false);")

			-- Delay setting up callbacks
			timer.Simple( 0.05, function()
				if IsValid(self) then self:SetupCallbacks() end
			end )

			self:OnStartLoading()
			self._loading = true
			
		end

	else

		-- Call finished loading
		if self._loading then

			-- Get the page URL
			self:RunJavascript("gmod.getUrl(window.location.href, true);")

			-- Hack to add window object callbacks
			if self.Callbacks.window then

				for funcname, callback in pairs(self.Callbacks.window) do
					local js = JS_CallbackHack
					js = js:format(funcname)
					self:RunJavascript(js)
				end

			end

			self:OnFinishLoading()
			self._loading = nil

		end

		-- Run queued javascript
		if self.JS then
			for k, v in pairs( self.JS ) do
				self:RunJavascript( v )
			end
			self.JS = nil
		end

	end

end

function PANEL:OnStartLoading()

end

function PANEL:OnFinishLoading()

end

function PANEL:QueueJavascript( js )

	--
	-- Can skip using the queue if there's nothing else in it
	--
	if ( !self.JS && !self:IsLoading() ) then
		return self:RunJavascript( js )
	end

	self.JS = self.JS or {}

	table.insert( self.JS, js )
	self:Think();

end

PANEL.QueueJavaScript = PANEL.QueueJavascript
PANEL.Call = PANEL.QueueJavascript

function PANEL:ConsoleMessage( msg, func )

	if ( !isstring( msg ) ) then msg = "*js variable*" end

	if ( self.m_bAllowLua && msg:StartWith( "RUNLUA:" ) ) then
	
		local strLua = msg:sub( 8 )

		SELF = self
		RunString( strLua )
		SELF = nil
		return; 

	end

	-- Filter messages output to the console
	-- 'console.gmod' always gets output
	local filterLevel = FilterCVar:GetInt()
	if ( func != "gmod" and filterLevel == FILTER_ALL ) then return end

	local prefixColor = ConsoleColors.default
	local prefix = "[HTML"
	if func and func:len() > 0 and func ~= "log" then
		if ConsoleColors[func] then
			prefixColor = ConsoleColors[func]
		end
		prefix = prefix .. "::" .. func:upper()
	end
	prefix = prefix .. "] "

	MsgC( prefixColor, prefix )
	MsgC( ConsoleColors.text, msg, "\n" )	

end

local JSObjects = {
	window 	= "_gm",
	this 	= "_gm",
	_gm = "window"
}

--
-- Called by the engine when a callback function is called
--
function PANEL:OnCallback( obj, func, args )

	-- Hack for adding window callbacks
	obj = JSObjects[obj] or obj

	if not self.Callbacks[ obj ] then return end

	--
	-- Use AddFunction to add functions to this.
	--
	local f = self.Callbacks[ obj ][ func ]

	if ( f ) then
		return f( unpack( args ) )
	end

end

--
-- Add a function to Javascript
--
function PANEL:AddFunction( obj, funcname, func )

	if obj == "this" then
		obj = "window"
	end

	--
	-- Create the `object` if it doesn't exist
	--
	if ( !self.Callbacks[ obj ] ) then
		self:NewObject( obj )
		self.Callbacks[ obj ] = {}
	end

	--
	-- This creates the function in javascript (which redirects to c++ which calls OnCallback here)
	--
	self:NewObjectCallback( JSObjects[obj] or obj, funcname )

	--
	-- Store the function so OnCallback can find it and call it
	--
	self.Callbacks[ obj ][ funcname ] = func;

end

function PANEL:GetURL()
	return self.URL
end

function PANEL:HTMLBack()
	if self.CurrentPage <= 1 then return end
	self.CurrentPage = self.CurrentPage - 1
	self:OpenURL( self.History[ self.CurrentPage ], true )
end

function PANEL:HTMLForward()
	if self.CurrentPage == #self.History then return end
	self.CurrentPage = self.CurrentPage + 1
	self:OpenURL( self.History[ self.CurrentPage ], true )
end

function PANEL:OpeningURL( url )
end

function PANEL:FinishedURL( url )
end

derma.DefineControl( "TheaterHTML", "Extended DHTML control", PANEL, "Awesomium" )
