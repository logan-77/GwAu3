#include-once

; Global storage for all active detours
Global $g_sd_Detours = ObjCreate("Scripting.Dictionary")
Global $g_p_PostMessageA

Global $g_b_AddPattern
Global $g_b_Scanner
Global $g_b_InitializeResult
Global $g_b_Assembler
Global $g_b_AssemblerData

Global $g_s_ChatReceive
Global $g_s_ChatLogBase
Global $g_i_ChatLogCounter
Global $g_i_ChatMessageChannel
Global $g_d_ChatLogStruct = DllStructCreate("dword;wchar[256]")
Global $g_p_ChatLogStruct = DllStructGetPtr($g_d_ChatLogStruct)

Func Extend_AddPattern()
	Scanner_AddPattern('PostMessage', '6AFF6A00680180', 0x19, 'Ptr')
	Scanner_AddPattern('ChatLog', '8B4508837D0C07', -0x20, 'Hook')
EndFunc

Func Extend_Scanner()
	$g_p_PostMessageA = Scanner_GetScanResult('PostMessage', $g_ap_ScanResults, 'Ptr')
	Memory_SetValue('PostMessage', Ptr(Memory_Read($g_p_PostMessageA, 'dword')))

	$l_p_Temp = Scanner_GetScanResult('ChatLog', $g_ap_ScanResults, 'Hook')
	Memory_SetValue('ChatLogStart', Ptr($l_p_Temp))
	Memory_SetValue('ChatLogReturn', Ptr($l_p_Temp + 0x5))

	;Hook log
	Log_Debug("PostMessage: " & Memory_GetValue('PostMessage'), "Initialize", $g_h_EditText)
	Log_Debug("ChatLogStart: " & Memory_GetValue('ChatLogStart'), "Initialize", $g_h_EditText)
	Log_Debug("ChatLogReturn: " & Memory_GetValue('ChatLogReturn'), "Initialize", $g_h_EditText)

    Memory_SetValue('CallbackEvent', '0x00000501')
	Memory_SetValue("ChatLogSize", "0x00000010")
EndFunc

Func Extend_InitializeResult()
	$mGUI = GUICreate('GwAu3')
	GUIRegisterMsg(0x00000501, 'CallBack_Event')
	Memory_Write(Memory_GetValue('CallbackHandle'), $mGUI)
	Log_Debug("CallbackHandle at: " & Memory_GetValue('CallbackHandle'), "Initialize", $g_h_EditText)

	$g_s_ChatLogBase = Memory_GetValue("ChatLogBase")
	$g_i_ChatLogCounter = Memory_GetValue("ChatMessageCounter")
	$g_i_ChatMessageChannel = Memory_GetValue("ChatMessageChannel")
EndFunc

Func Extend_Assembler()
	Assembler_CreateChatLog()
EndFunc

Func Assembler_CreateEventData()
    _('CallbackHandle/4')
	_('CallbackEvent/4')

	_("ChatLogLastMsg/4")
	_("ChatLogCounter/4")
	_("ChatMessageCounter/4")
	_("ChatMessageChannel/4")

	_("ChatLogBase/" & 512)
EndFunc

Func Extend_AssemblerData()
	Assembler_CreateEventData()
EndFunc

Func Memory_WriteDetourEx($a_s_FromLabel, $a_s_ToLabel)
    Local $l_p_LabelPtr = Memory_GetValue($a_s_FromLabel)
    Local $l_s_Buffer = DllStructCreate("byte[5]")
    DllCall($g_h_Kernel32, "bool", "ReadProcessMemory", _
        "handle", $g_h_GWProcess, _
        "ptr", $l_p_LabelPtr, _
        "ptr", DllStructGetPtr($l_s_Buffer), _
        "ulong_ptr", 5, _
        "ulong_ptr*", 0 _
    )
    Local $l_s_OriginalOpcode = ""
    For $i = 1 To 5
        $l_s_OriginalOpcode &= Hex( DllStructGetData($l_s_Buffer, 1, $i), 2 )
    Next
    $g_sd_Detours.Add($a_s_FromLabel, $l_s_OriginalOpcode)
    Memory_WriteBinary('E9' & Utils_SwapEndian(Hex(Memory_GetValue($a_s_ToLabel) - Memory_GetValue($a_s_FromLabel) - 5)), Memory_GetValue($a_s_FromLabel))
EndFunc

Func Memory_RevertDetour($a_s_FromLabel)
    If Not $g_sd_Detours.Exists($a_s_FromLabel) Then Return 0

    Local $l_s_OriginalOpcode = $g_sd_Detours.Item($a_s_FromLabel)
    Local $l_p_LabelPtr = Memory_GetValue($a_s_FromLabel)

    Memory_WriteBinary($l_s_OriginalOpcode, $l_p_LabelPtr)
    $g_sd_Detours.Remove($a_s_FromLabel)

    Return True
EndFunc

Func CallBack_SetEvent($a_s_ChatReceive = '')
	If $a_s_ChatReceive <> "" Then
		Memory_WriteDetourEx("ChatLogStart", "ChatLogProc")
	Else
		Memory_RevertDetour("ChatLogStart")
	EndIf

	$g_s_ChatReceive = $a_s_ChatReceive

    Log_Info("Event callbacks configured", "CallBack_SetEvent", $g_h_EditText)
EndFunc

Func CallBack_Event($hWnd, $msg, $wparam, $lparam)
    Switch $lparam
		Case 0x1
			DllCall($g_h_Kernel32, "int", "ReadProcessMemory", "int", $g_h_GWProcess, "int", $wparam, "ptr", $g_p_ChatLogStruct, "int", 512, "int", "")
			Local $l_s_Message = DllStructGetData($g_d_ChatLogStruct, 2)
			Local $l_s_Channel = ""
			Local $l_s_Sender = ""
			Local $l_s_GuildTag = "No"
			Local $i_ChannelType = DllStructGetData($g_d_ChatLogStruct, 1)

			Switch $i_ChannelType
				Case 0
					$l_s_Channel = "Alliance"
					_ParseAlliance($l_s_Message, $l_s_Sender, $l_s_GuildTag, $l_s_Message)
				Case 3
					$l_s_Channel = "All"
					_ParseStandard($l_s_Message, $l_s_Sender, $l_s_Message)
				Case 9
					$l_s_Channel = "Guild"
					_ParseStandard($l_s_Message, $l_s_Sender, $l_s_Message, "ċĈć")
				Case 11
					$l_s_Channel = "Team"
					_ParseStandard($l_s_Message, $l_s_Sender, $l_s_Message)
				Case 12
					$l_s_Channel = "Trade"
					_ParseStandard($l_s_Message, $l_s_Sender, $l_s_Message)
				Case 10
					$l_s_Channel = "Send Whisper"
					_ParseWhisper($l_s_Message, $l_s_Sender, $l_s_Message)
				Case 13
					$l_s_Channel = "Advisory"
					$l_s_Sender = "Guild Wars"
					$l_s_Message = ""
				Case 14
					$l_s_Channel = "Received Whisper"
					_ParseWhisper($l_s_Message, $l_s_Sender, $l_s_Message)
				Case Else
					$l_s_Channel = "Other"
					$l_s_Sender = "Other"
			EndSwitch
			Call($g_s_ChatReceive, $l_s_Channel, $l_s_Sender, $l_s_Message, $l_s_GuildTag)
			Log_Debug("Channel: " & $l_s_Channel & " Sender: " & $l_s_Sender & " Alliance: " & $l_s_GuildTag & " Message: " & $l_s_Message, "ChatCallback", $g_h_EditText)
	EndSwitch

    Return 0
EndFunc

Func Extend_CleanText($s_Text)
    Return StringRegExpReplace($s_Text, "[^\x20-\x7E]", "")
EndFunc

Func _ParseAlliance($msg, ByRef $sender, ByRef $tag, ByRef $text)
    $sender = StringLeft($msg, StringInStr($msg, "Ĉ") - 1)
    Local $start = StringInStr($msg, "Ĉ") + 2
    Local $end = StringInStr($msg, "ċĈć")
    $tag = StringMid($msg, $start, $end - $start)
    $text = StringMid($msg, $end + 5, StringInStr($msg, "", 0, 1, $end + 5) - ($end + 5))
    $sender = Extend_CleanText($sender)
    $tag = Extend_CleanText($tag)
    $text = Extend_CleanText($text)
EndFunc

Func _ParseStandard($msg, ByRef $sender, ByRef $text, $sep = "ċĈć")
    Local $sepPos = StringInStr($msg, $sep)
    $sender = StringMid($msg, 1, $sepPos - 1)
    $text = StringMid($msg, $sepPos + StringLen($sep), StringInStr($msg, "") - ($sepPos + StringLen($sep)))
    $sender = Extend_CleanText($sender)
    $text = Extend_CleanText($text)
EndFunc

Func _ParseWhisper($msg, ByRef $sender, ByRef $text)
    Local $sepPos = StringInStr($msg, "Ĉ")
    $sender = StringLeft($msg, $sepPos - 1)
    $text = StringMid($msg, $sepPos + 2, StringInStr($msg, "") - ($sepPos + 2))
    $sender = Extend_CleanText($sender)
    $text = Extend_CleanText($text)
EndFunc

Func Assembler_CreateChatLog()
	_("ChatLogProc:")
	_("mov ecx,esp")
	_("add ecx,C")
	_("mov ecx,dword[ecx]")
	_("add ecx,4")
	_("push ebx")
	_("mov ebx,0")
	_("mov eax,ChatLogBase")
	_("ChatLogCopyLoop:")
	_("mov dx,word[ecx]")
	_("mov word[eax],dx")
	_("add ecx,2")
	_("add eax,2")
	_("inc ebx")
	_("cmp ebx,FF")
	_("jz ChatLogCopyExit")
	_("test dx,dx")
	_("jnz ChatLogCopyLoop")
	_("ChatLogCopyExit:")
	_("pop ebx")
	_("mov ecx,esp")
	_("add ecx,10")
	_("mov ecx,dword[ecx]")
	_("mov dword[ChatMessageChannel],ecx")

	_("push eax")
	_("mov eax,ChatLogBase")
	_("sub eax,4")
	_("mov dword[eax],ecx")
	_("pop eax")

	_("mov ecx,dword[ChatMessageCounter]")
	_("add ecx,1")
	_("mov dword[ChatMessageCounter],ecx")

	_("pushad")
	_("push 1")
	_("mov eax,ChatLogBase")
	_("sub eax,4")
	_("push eax")
	_("push CallbackEvent")
	_("push dword[CallbackHandle]")
	_("call dword[PostMessage]")
	_("popad")

	_("mov eax,dword[ebp+8]")
	_("test eax,eax")
	_("ljmp ChatLogReturn")
EndFunc

Func Assembler_CreateChatLog_()
    _('ChatLogProc:')
    _("pushfd")
    _("pushad")

    ; Recover the original ESP (at hook entry) from pushad's saved ESP slot
    ; pushad layout at current ESP:
    ; [esp+00]=EDI [esp+04]=ESI [esp+08]=EBP [esp+0C]=savedESP [esp+10]=EBX [esp+14]=EDX [esp+18]=ECX [esp+1C]=EAX
    _("mov esi,dword[esp+C]")      ; esi = savedESP (ESP after pushfd)
    _("add esi,4")                 ; esi = original ESP at hook entry

    _("mov ecx,dword[esi+C]")      ; ecx = *(orig_esp+0x0C)
    _("add ecx,4")                 ; ecx += 4

    ; Channel from the original stack slot
    _("mov edi,dword[esi+10]")     ; edi = *(orig_esp+0x10)

    _("xor ebx,ebx")
    _("mov eax,ChatLogBase")

    _("ChatLogCopyLoop:")
    _("mov dx,word[ecx]")
    _("mov word[eax],dx")
    _("add ecx,2")
    _("add eax,2")
    _("inc ebx")
    _("cmp ebx,FF")
    _("jz ChatLogCopyExit")
    _("test dx,dx")
    _("jnz ChatLogCopyLoop")

    _("ChatLogCopyExit:")

    _("mov dword[ChatMessageChannel],edi")

    _("push eax")
    _("mov eax,ChatLogBase")
    _("sub eax,4")
    _("mov dword[eax],edi")
    _("pop eax")

    _("mov edx,dword[ChatMessageCounter]")
    _("inc edx")
    _("mov dword[ChatMessageCounter],edx")

    ; cdecl callback/post wrapper (caller cleans stack)
    _("push 1")
    _("mov edx,ChatLogBase")
    _("sub edx,4")
    _("push edx")
    _("push CallbackEvent")
    _("push dword[CallbackHandle]")
    _("call dword[PostMessage]")
    _("add esp,10")                ; 4 args * 4 bytes

    ; Restore original CPU state
    _("popad")
    _("popfd")

    ; Displaced original bytes
    _("mov eax,dword[ebp+8]")      ; original
    _("test eax,eax")              ; original

    _("ljmp ChatLogReturn")
EndFunc

Func GetChatLogBase()
    Return $g_s_ChatLogBase
EndFunc

Func GetChatMessageCounter()
    Return Memory_Read($g_i_ChatLogCounter)
EndFunc

Func GetChatMessageChannel()
    Return Memory_Read($g_i_ChatMessageChannel)
EndFunc