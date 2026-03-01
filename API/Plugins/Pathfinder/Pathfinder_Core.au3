#include-once
#include <InetConstants.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <ProgressConstants.au3>

Global $DLL_PATH = ""
Global $g_hPathfinderDLL = 0  ; Handle to loaded DLL
Global $g_bPathfinder_Debug = False  ; Debug logging (can be enabled from Pathfinder_Movements.au3)

; URL to download maps.rar from (set this before calling Pathfinder_Initialize)
Global $g_sPathfinder_MapsURL = "https://drive.google.com/file/d/1u621EmOBIr5cInGFLdzOcEzsxr-z2VzO/view?usp=sharing"

Global Const $tagPathPoint = "float x;float y;int layer;int tp_type"
Global Const $tagPathResult = "ptr points;int point_count;float total_cost;int error_code;char error_message[256]"
Global Const $tagMapStats = "int trapezoid_count;int point_count;int teleport_count;int travel_portal_count;int npc_travel_count;int enter_travel_count;int error_code;char error_message[256]"
Global Const $tagObstacleZone = "float x;float y;float radius"


; Returns:
;   1 = OK (maps.rar or maps/ found)
;   2 = OK but no maps source found (maps.rar and maps/ missing)
;   0 = Failed (DLL error)
Func Pathfinder_Initialize()
    If $g_bPathfinder_Debug Then Out("[Pathfinder] Initialize - DLL_PATH=" & $DLL_PATH)

    ; Check if maps.rar exists next to the DLL, download if missing
    Local $sDllDir = StringRegExpReplace($DLL_PATH, "\\[^\\]+$", "")
    Local $sMapsPath = $sDllDir & "\maps.rar"
    Local $sMapsDir = $sDllDir & "\maps"

    If Not FileExists($sMapsPath) And Not FileExists($sMapsDir) Then
        If $g_bPathfinder_Debug Then Out("[Pathfinder] maps.rar not found at: " & $sMapsPath)
        If $g_sPathfinder_MapsURL <> "" Then
            If $g_bPathfinder_Debug Then Out("[Pathfinder] Downloading maps.rar...")
            If Not Pathfinder_DownloadMaps($sMapsPath) Then
                Out("[Pathfinder] ERROR: Download failed!")
            EndIf
        Else
            If $g_bPathfinder_Debug Then Out("[Pathfinder] No download URL configured, skipping download")
        EndIf
    EndIf

    ; Load DLL if not already loaded
    If $g_hPathfinderDLL = 0 Or $g_hPathfinderDLL = -1 Then
        $g_hPathfinderDLL = DllOpen($DLL_PATH)
        If $g_hPathfinderDLL = -1 Then
            If $g_bPathfinder_Debug Then Out("[Pathfinder] ERROR: DllOpen failed for " & $DLL_PATH)
            Return 0
        EndIf
        If $g_bPathfinder_Debug Then Out("[Pathfinder] DLL loaded OK, handle=" & $g_hPathfinderDLL)
    EndIf

    Local $result = DllCall($g_hPathfinderDLL, "int:cdecl", "Initialize")
    If @error Then
        If $g_bPathfinder_Debug Then Out("[Pathfinder] ERROR: DllCall Initialize failed, @error=" & @error)
        Return 0
    EndIf

    If $g_bPathfinder_Debug Then Out("[Pathfinder] DLL Initialize returned: " & $result[0] & " (1=OK, 2=no maps, 0=error)")
    Return $result[0]
EndFunc

; Converts a Google Drive share URL to a direct download URL
; Input:  https://drive.google.com/file/d/{ID}/view?usp=...
; Output: https://drive.usercontent.google.com/download?id={ID}&export=download&confirm=t
Func _Pathfinder_GetDirectURL($a_sURL)
    ; Extract Google Drive file ID
    Local $aMatch = StringRegExp($a_sURL, "drive\.google\.com/file/d/([^/]+)", 1)
    If Not @error Then
        Return "https://drive.usercontent.google.com/download?id=" & $aMatch[0] & "&export=download&confirm=t"
    EndIf
    ; Not a Google Drive URL, return as-is (direct link)
    Return $a_sURL
EndFunc

; Downloads maps.rar from $g_sPathfinder_MapsURL with progress bar
; Returns: True on success, False on failure
Func Pathfinder_DownloadMaps($a_sDestPath)
    If $g_sPathfinder_MapsURL = "" Then
        If $g_bPathfinder_Debug Then Out("[Pathfinder] DownloadMaps: No URL configured")
        Return False
    EndIf

    Local $sDownloadURL = _Pathfinder_GetDirectURL($g_sPathfinder_MapsURL)
    If $g_bPathfinder_Debug Then Out("[Pathfinder] DownloadMaps: Direct URL = " & $sDownloadURL)

    If $g_bPathfinder_Debug Then Out("[Pathfinder] DownloadMaps: Dest = " & $a_sDestPath)

    ; Create progress GUI
    Local $hGUI = GUICreate("Pathfinder - Downloading maps.rar", 450, 100)
    Local $hLabel = GUICtrlCreateLabel("Downloading maps.rar... Connecting...", 20, 15, 410, 20)
    Local $hProgress = GUICtrlCreateProgress(20, 45, 410, 25)
    GUISetState(@SW_SHOW, $hGUI)

    ; Start background download
    Local $hDownload = InetGet($sDownloadURL, $a_sDestPath, $INET_FORCERELOAD, $INET_DOWNLOADBACKGROUND)
    If $g_bPathfinder_Debug Then Out("[Pathfinder] DownloadMaps: InetGet handle = " & $hDownload)

    ; Poll download progress until complete
    While Not InetGetInfo($hDownload, $INET_DOWNLOADCOMPLETE)
        Local $iBytesRead = InetGetInfo($hDownload, $INET_DOWNLOADREAD)
        Local $iBytesTotal = InetGetInfo($hDownload, $INET_DOWNLOADSIZE)

        If $iBytesTotal > 0 Then
            Local $iPercent = Int($iBytesRead / $iBytesTotal * 100)
            GUICtrlSetData($hProgress, $iPercent)
            GUICtrlSetData($hLabel, "Downloading maps.rar... " & Round($iBytesRead / 1048576) & " / " & Round($iBytesTotal / 1048576) & " MB (" & $iPercent & "%)")
        Else
            GUICtrlSetData($hLabel, "Downloading maps.rar... " & Round($iBytesRead / 1048576) & " MB")
        EndIf

        Sleep(200)
    WEnd

    Local $bSuccess = InetGetInfo($hDownload, $INET_DOWNLOADSUCCESS)
    Local $iBytesRead = InetGetInfo($hDownload, $INET_DOWNLOADREAD)
    InetClose($hDownload)
    GUIDelete($hGUI)

    If $g_bPathfinder_Debug Then Out("[Pathfinder] DownloadMaps: Complete. Success=" & $bSuccess & " BytesRead=" & $iBytesRead)

    If Not $bSuccess Then
        If $g_bPathfinder_Debug Then Out("[Pathfinder] DownloadMaps: FAILED - cleaning up partial file")
        FileDelete($a_sDestPath)
        Return False
    EndIf

    ; Verify file is not a Google Drive HTML page (< 10 MB means it's not the real file)
    If $iBytesRead < 10485760 Then ; 10 MB
        If $g_bPathfinder_Debug Then Out("[Pathfinder] DownloadMaps: FAILED - file too small (" & $iBytesRead & " bytes), likely a Google Drive error page")
        FileDelete($a_sDestPath)
        Return False
    EndIf

    If $g_bPathfinder_Debug Then Out("[Pathfinder] DownloadMaps: File saved OK (" & Round($iBytesRead / 1048576) & " MB)")
    Return True
EndFunc

Func Pathfinder_Shutdown()
    If $g_hPathfinderDLL <> 0 And $g_hPathfinderDLL <> -1 Then
        DllCall($g_hPathfinderDLL, "none:cdecl", "Shutdown")
        DllClose($g_hPathfinderDLL)
        $g_hPathfinderDLL = 0
    EndIf
EndFunc

Func Pathfinder_FreePathResult($pResult)
    If $pResult = 0 Or $pResult = Null Then Return
    If $g_hPathfinderDLL = 0 Or $g_hPathfinderDLL = -1 Then Return
    DllCall($g_hPathfinderDLL, "none:cdecl", "FreePathResult", "ptr", $pResult)
EndFunc

; Find a path with obstacle avoidance (Raw version - returns pointer)
; $aObstacles = 2D array [[x, y, radius], [x, y, radius], ...]
; $startLayer = layer of the starting point (-1 = auto-detect)
Func Pathfinder_FindPathRaw($mapID, $startX, $startY, $startLayer, $destX, $destY, $destLayer = -1, $aObstacles = 0, $simplifyRange = 1250, $clearanceWeight = 0.0)
    ; Verify DLL is loaded
    If $g_hPathfinderDLL = 0 Or $g_hPathfinderDLL = -1 Then
        If $g_bPathfinder_Debug Then Out("[Pathfinder DLL] ERROR: DLL not loaded" & @CRLF)
        Return SetError(1, 0, 0)
    EndIf

    Local $obstacleCount = 0
    Local $pObstacles = 0

    ; Check if obstacles are provided and have valid format (2D array with 3 columns)
    If IsArray($aObstacles) And UBound($aObstacles) > 0 Then
        ; Validate array format: must be 2D with at least 3 columns
        If UBound($aObstacles, 0) = 2 And UBound($aObstacles, 2) >= 3 Then
            $obstacleCount = UBound($aObstacles)

            ; Create a contiguous array of ObstacleZone structures in memory
            ; Each ObstacleZone is 12 bytes (3 floats: x, y, radius)
            Local $obstacleStructSize = 12
            Local $obstacleBuffer = DllStructCreate("byte[" & ($obstacleCount * $obstacleStructSize) & "]")
            $pObstacles = DllStructGetPtr($obstacleBuffer)

            ; Fill the obstacle buffer
            For $i = 0 To $obstacleCount - 1
                Local $obstacle = DllStructCreate($tagObstacleZone, $pObstacles + $i * $obstacleStructSize)
                DllStructSetData($obstacle, "x", $aObstacles[$i][0])
                DllStructSetData($obstacle, "y", $aObstacles[$i][1])
                DllStructSetData($obstacle, "radius", $aObstacles[$i][2])
            Next
        Else
            ; Invalid format - ignore obstacles to prevent crash
            If $g_bPathfinder_Debug Then Out("[Pathfinder DLL] WARNING: Invalid obstacle array format, ignoring obstacles" & @CRLF)
        EndIf
    EndIf

    ; Call FindPathWithObstacles
    Local $result = DllCall($g_hPathfinderDLL, "ptr:cdecl", "FindPathWithObstacles", _
        "int", $mapID, _
        "float", $startX, _
        "float", $startY, _
        "int", $startLayer, _
        "float", $destX, _
        "float", $destY, _
        "int", $destLayer, _
        "ptr", $pObstacles, _
        "int", $obstacleCount, _
        "float", $simplifyRange, _
        "float", $clearanceWeight)

    If @error Then
        Return SetError(1, 0, 0)
    EndIf

    Return $result[0]
EndFunc

; Find a path with obstacle avoidance (returns 2D array of coordinates)
; $aObstacles = 2D array [[x, y, radius], [x, y, radius], ...]
; $startLayer = layer of the starting point (-1 = auto-detect)
Func Pathfinder_FindPath($mapID, $startX, $startY, $startLayer, $destX, $destY, $destLayer = -1, $aObstacles = 0, $simplifyRange = 1250, $clearanceWeight = 0.0)
    Local $l_p_Result = Pathfinder_FindPathRaw($mapID, $startX, $startY, $startLayer, $destX, $destY, $destLayer, $aObstacles, $simplifyRange, $clearanceWeight)

    If $l_p_Result = 0 Then
        If $g_bPathfinder_Debug Then Out("[Pathfinder DLL] ERROR: DllCall returned null pointer" & @CRLF)
        Return SetError(1, 0, 0)
    EndIf

    Local $l_t_Result = DllStructCreate($tagPathResult, $l_p_Result)
    Local $l_i_ErrorCode = DllStructGetData($l_t_Result, "error_code")

    If $l_i_ErrorCode <> 0 Then
        Local $l_s_ErrorMsg = DllStructGetData($l_t_Result, "error_message")
        If $g_bPathfinder_Debug Then Out("[Pathfinder DLL] ERROR code=" & $l_i_ErrorCode & " msg=" & $l_s_ErrorMsg & @CRLF)
        Pathfinder_FreePathResult($l_p_Result)
        Return SetError(2, $l_i_ErrorCode, 0)
    EndIf

    Local $l_i_PointCount = DllStructGetData($l_t_Result, "point_count")
    Local $l_p_Points = DllStructGetData($l_t_Result, "points")

    If $g_bPathfinder_Debug Then Out("[Pathfinder DLL] OK: point_count=" & $l_i_PointCount & @CRLF)

    ; Validate point count and pointer
    If $l_i_PointCount <= 0 Or $l_p_Points = 0 Or $l_p_Points = Null Then
        If $g_bPathfinder_Debug Then Out("[Pathfinder DLL] ERROR: Invalid point data" & @CRLF)
        Pathfinder_FreePathResult($l_p_Result)
        Return SetError(3, 0, 0)
    EndIf

    ; Limit point count to prevent memory issues (max 10000 points)
    If $l_i_PointCount > 10000 Then
        If $g_bPathfinder_Debug Then Out("[Pathfinder DLL] WARNING: Point count too high, limiting to 10000" & @CRLF)
        $l_i_PointCount = 10000
    EndIf

    Local $a_Path[$l_i_PointCount][4]  ; x, y, layer, tp_type
    For $i = 0 To $l_i_PointCount - 1
        Local $l_t_Point = DllStructCreate($tagPathPoint, $l_p_Points + ($i * 16))  ; 16 bytes: float x (4) + float y (4) + int layer (4) + int tp_type (4)
        $a_Path[$i][0] = DllStructGetData($l_t_Point, "x")
        $a_Path[$i][1] = DllStructGetData($l_t_Point, "y")
        $a_Path[$i][2] = DllStructGetData($l_t_Point, "layer")
        $a_Path[$i][3] = DllStructGetData($l_t_Point, "tp_type")
    Next

    Pathfinder_FreePathResult($l_p_Result)

    Return $a_Path
EndFunc

Func Pathfinder_IsMapAvailable($mapID)
    If $g_hPathfinderDLL = 0 Or $g_hPathfinderDLL = -1 Then Return False
    Local $result = DllCall($g_hPathfinderDLL, "int:cdecl", "IsMapAvailable", "int", $mapID)
    If @error Then Return False
    Return $result[0] = 1
EndFunc

Func Pathfinder_GetAvailableMaps()
    If $g_hPathfinderDLL = 0 Or $g_hPathfinderDLL = -1 Then Return SetError(1, 0, 0)

    Local $count = 0
    Local $result = DllCall($g_hPathfinderDLL, "ptr:cdecl", "GetAvailableMaps", "int*", $count)
    If @error Or $result[0] = 0 Then
        Return SetError(1, 0, 0)
    EndIf

    Local $pMapList = $result[0]
    $count = $result[1]

    ; Validate count
    If $count <= 0 Or $count > 10000 Then
        DllCall($g_hPathfinderDLL, "none:cdecl", "FreeMapList", "ptr", $pMapList)
        Return SetError(2, 0, 0)
    EndIf

    Local $mapIds[$count]
    For $i = 0 To $count - 1
        $mapIds[$i] = DllStructGetData(DllStructCreate("int", $pMapList + $i * 4), 1)
    Next

    DllCall($g_hPathfinderDLL, "none:cdecl", "FreeMapList", "ptr", $pMapList)

    Return $mapIds
EndFunc

Func Pathfinder_GetMapStats($mapID)
    If $g_hPathfinderDLL = 0 Or $g_hPathfinderDLL = -1 Then Return SetError(1, 0, 0)

    Local $result = DllCall($g_hPathfinderDLL, "ptr:cdecl", "GetMapStats", "int", $mapID)
    If @error Or $result[0] = 0 Then
        Return SetError(1, 0, 0)
    EndIf

    Local $pStats = $result[0]
    Local $stats = DllStructCreate($tagMapStats, $pStats)

    Local $statsArray[7]
    $statsArray[0] = DllStructGetData($stats, "trapezoid_count")
    $statsArray[1] = DllStructGetData($stats, "point_count")
    $statsArray[2] = DllStructGetData($stats, "teleport_count")
    $statsArray[3] = DllStructGetData($stats, "travel_portal_count")
    $statsArray[4] = DllStructGetData($stats, "npc_travel_count")
    $statsArray[5] = DllStructGetData($stats, "enter_travel_count")
    $statsArray[6] = DllStructGetData($stats, "error_code")

    DllCall($g_hPathfinderDLL, "none:cdecl", "FreeMapStats", "ptr", $pStats)

    Return $statsArray
EndFunc
