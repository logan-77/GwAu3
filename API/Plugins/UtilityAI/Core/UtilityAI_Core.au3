#include-once

Func UAI_Fight($a_f_x, $a_f_y, $a_f_AggroRange = 1320, $a_f_MaxDistanceToXY = 3500, _
	$a_i_FightMode = $g_i_FinisherMode, $a_b_UseSwitchSet = False, _
	$a_v_PlayerNumber = 0, $a_b_KillOnly = False, _
	$a_s_ExitCallback = "", $a_i_CallTargetMode = $GC_UAI_TARGET_MODE_CALL)
	
	$g_i_BestTarget = 0
	$g_i_ForceTarget = 0
	$g_i_LastCalledTarget = 0
	$g_i_FightMode = $a_i_FightMode
	$g_b_CacheWeaponSet = $a_b_UseSwitchSet
	$g_i_TargetMode = $a_i_CallTargetMode
	$g_v_AvoidPlayerNumbers = -1

	Local $l_i_MyOldMap = Map_GetMapID(), $l_i_MapLoadingOld = Map_GetInstanceInfo("Type")
	Local $l_v_PriorityTargets = 0

	If IsArray($a_v_PlayerNumber) Then
		Local $l_a_Prio[UBound($a_v_PlayerNumber)]
		Local $l_a_Avoid[UBound($a_v_PlayerNumber)]
		Local $l_i_PC = 0, $l_i_AC = 0
		For $j = 0 To UBound($a_v_PlayerNumber) - 1
			If $a_v_PlayerNumber[$j] > 0 Then
				$l_a_Prio[$l_i_PC] = $a_v_PlayerNumber[$j]
				$l_i_PC += 1
			ElseIf $a_v_PlayerNumber[$j] < 0 Then
				$l_a_Avoid[$l_i_AC] = Abs($a_v_PlayerNumber[$j])
				$l_i_AC += 1
			EndIf
		Next
		If $l_i_PC > 0 Then
			ReDim $l_a_Prio[$l_i_PC]
			$l_v_PriorityTargets = $l_a_Prio
		EndIf
		If $l_i_AC > 0 Then
			ReDim $l_a_Avoid[$l_i_AC]
			$g_v_AvoidPlayerNumbers = $l_a_Avoid
		EndIf
	ElseIf $a_v_PlayerNumber > 0 Then
		$l_v_PriorityTargets = $a_v_PlayerNumber
	ElseIf $a_v_PlayerNumber < 0 Then
		$g_v_AvoidPlayerNumbers = Abs($a_v_PlayerNumber)
	EndIf

	Local $l_b_HasPriority = IsArray($l_v_PriorityTargets) Or $l_v_PriorityTargets <> 0

	If $l_b_HasPriority Then
		UAI_UpdateCache($a_f_AggroRange)
		$g_i_ForceTarget = UAI_FindAgentByPlayerNumber($l_v_PriorityTargets, -2, $a_f_AggroRange, "UAI_Filter_IsLivingEnemy")
		If $g_i_ForceTarget = 0 And $a_b_KillOnly Then Return True
	EndIf

	If $g_b_CacheWeaponSet Then UAI_DeterminateWeaponSets()

	Do
		If Agent_GetDistanceToXY($a_f_x, $a_f_y) > $a_f_AggroRange Then ExitLoop
		If $g_i_ForceTarget <> 0 And UAI_GetAgentInfoByID($g_i_ForceTarget, $GC_UAI_AGENT_IsDead) Then
			$g_i_ForceTarget = UAI_FindAgentByPlayerNumber($l_v_PriorityTargets, -2, $a_f_AggroRange, "UAI_Filter_IsLivingEnemy")
			If $g_i_ForceTarget = 0 And $a_b_KillOnly Then ExitLoop
		EndIf
		If $g_i_TargetMode = $GC_UAI_TARGET_MODE_FOLLOW Then
			Local $l_i_FollowTarget = UAI_GetPartyCalledTarget()
			If $l_i_FollowTarget <> 0 Then $g_i_ForceTarget = $l_i_FollowTarget
		EndIf
		UAI_UseSkills($a_f_x, $a_f_y, $a_f_AggroRange, $a_f_MaxDistanceToXY)
	Until UAI_CountEnemyInPartyAggroRange($a_f_AggroRange) = 0 Or Agent_GetAgentInfo(-2, "IsDead") Or Party_IsWiped() Or Map_GetMapID() <> $l_i_MyOldMap Or Map_GetInstanceInfo("Type") <> $l_i_MapLoadingOld Or ($a_s_ExitCallback <> "" And Call($a_s_ExitCallback))
EndFunc   ;==>UAI_Fight

;~ Use this function to cast all of your skills or skills of a certain type.
Func UAI_UseSkills($a_f_x, $a_f_y, $a_f_AggroRange = 1320, $a_f_MaxDistanceToXY = 3500)
	;~ Static $ls_i_LowPrioSkill = 6
	For $skillSlot = 1 To 8
		If UAI_GetStaticSkillInfo($skillSlot, $GC_UAI_STATIC_SKILL_SkillID) = 0 Then ContinueLoop

;~ 	UPDATE CACHE FIRST
		UAI_UpdateCache($a_f_AggroRange)
		If Not UAI_IsEnemyInPartyAggroRange($a_f_AggroRange) Then ExitLoop
		If $g_b_CacheWeaponSet Then UAI_ShouldSwitchWeaponSet()

;~ 	CHECK PARTY
		If UAI_GetPlayerInfo($GC_UAI_AGENT_IsDead) Or Party_IsWiped() = 1 Or Map_GetInstanceInfo("Type") <> $GC_I_MAP_TYPE_EXPLORABLE Or UAI_GetPlayerInfo($GC_UAI_AGENT_IsKnockedDown) Then Return

		If $g_b_SkillChanged = True And Cache_EndFormChangeBuild($skillSlot) Then $g_b_SkillChanged = False

;~ 	MOVE TOWARD HERO AGGRO TARGET
		; If no enemy is in the player's range but a hero has aggro on one, move toward it.
		; Only chase while the player is still within aggro range of the fight origin.
		If Not UAI_IsAgentInRange(-2, $a_f_AggroRange, "UAI_Filter_IsLivingEnemy|UAI_Filter_IsNotAvoided") _
			And Agent_GetDistanceToXY($a_f_x, $a_f_y) <= $a_f_AggroRange Then

			Local $l_i_PartyRangeEnemy = UAI_GetNearestEnemyInPartyRange($a_f_AggroRange)
			If $l_i_PartyRangeEnemy <> 0 Then
				Local $l_f_EnemyX = UAI_GetAgentInfoByID($l_i_PartyRangeEnemy, $GC_UAI_AGENT_X)
				Local $l_f_EnemyY = UAI_GetAgentInfoByID($l_i_PartyRangeEnemy, $GC_UAI_AGENT_Y)
				Map_Move($l_f_EnemyX, $l_f_EnemyY, 0)
				Sleep(500)
				ExitLoop
			EndIf
		EndIf

;~ 	AUTO ATTACK
		If UAI_CanAutoAttack() Then
			Local $l_i_AttackTarget = 0

			If $g_i_ForceTarget <> 0 Then
				$l_i_AttackTarget = $g_i_ForceTarget
			ElseIf $g_i_AttackTarget <> 0 And Not UAI_GetAgentInfoByID($g_i_AttackTarget, $GC_UAI_AGENT_IsDead) Then
				$l_i_AttackTarget = $g_i_AttackTarget
			Else
				$l_i_AttackTarget = UAI_GetNearestAgent(-2, $a_f_AggroRange, "UAI_Filter_IsLivingEnemy|UAI_Filter_IsNotAvoided")
			EndIf

			If $l_i_AttackTarget <> 0 Then Agent_Attack($l_i_AttackTarget, False)
			$g_i_AttackTarget = $l_i_AttackTarget

			If $g_i_LastCalledTarget = 0 Then
				Agent_CallTarget($l_i_AttackTarget)
				$g_i_LastCalledTarget = $l_i_AttackTarget
			EndIf
		Else
			If UAI_GetPlayerInfo($GC_UAI_AGENT_IsAttacking) Then Core_ControlAction($GC_I_CONTROL_ACTION_CANCEL_ACTION)
		EndIf

;~ 	PRIORITY SKILLS
		UAI_PrioritySkills($a_f_AggroRange)

;~ 	BUNDLE TO DROP
		UAI_DropBundle($a_f_AggroRange)

;~ 	NORMAL SKILLS
		UAI_TryUseSkill($skillSlot, $a_f_AggroRange)

;~ 	MOVE IF TOO FAR
		If $a_f_MaxDistanceToXY <> 0 And Agent_GetDistanceToXY($a_f_x, $a_f_y) > $a_f_MaxDistanceToXY Then ExitLoop

		Sleep(128)
	Next

	Return True
EndFunc   ;==>UAI_UseSkills

; Stops after the first priority skill that was successfully used
Func UAI_PrioritySkills($a_f_AggroRange = 1320)
	For $i = 1 To $g_ai_PrioritySlots[0]
		If UAI_TryUseSkill($g_ai_PrioritySlots[$i], $a_f_AggroRange) Then
			UAI_UpdateCache($a_f_AggroRange)
			Return True
		EndIf
	Next

	Return False
EndFunc

; Tries to use the skill in $a_i_Slot: checks usability, resolves the target, and uses it if possible
Func UAI_TryUseSkill($a_i_Slot, $a_f_AggroRange = 1320)
	If Not UAI_CanUse($a_i_Slot) Then Return False

	$g_i_BestTarget = Call($g_as_BestTargetCache[$a_i_Slot], $a_f_AggroRange)
	Local $l_b_OverrideForceTarget = (@extended = $GC_I_UAI_OVERRIDE_FORCE_TARGET)
	If Not $l_b_OverrideForceTarget And $g_i_ForceTarget <> 0 And UAI_GetAgentInfoByID($g_i_BestTarget, $GC_UAI_AGENT_Allegiance) = $GC_I_ALLEGIANCE_ENEMY Then
		$g_i_BestTarget = $g_i_ForceTarget
	EndIf

	If $g_i_BestTarget = 0 Then Return False
	If Not UAI_Filter_IsNotAvoided($g_i_BestTarget) Then Return False

	$g_b_CanUseSkill = Call($g_as_CanUseCache[$a_i_Slot])
	If Not ($g_b_CanUseSkill And Agent_GetDistance($g_i_BestTarget) < $a_f_AggroRange) Then Return False

	UAI_UseSkillEx($a_i_Slot, $g_i_BestTarget, $a_f_AggroRange)
	If Cache_FormChangeBuild($a_i_Slot) Then $g_b_SkillChanged = True
	
	Return True
EndFunc

; Use skill function
Func UAI_UseSkillEx($a_i_SkillSlot, $a_i_AgentID = -2, $a_f_AggroRange = 1320)
	Local $l_i_MyID = Agent_GetMyID()
	If $a_i_AgentID <> $l_i_MyID Then Agent_ChangeTarget($a_i_AgentID)
	If $g_b_CacheWeaponSet Then UAI_GetBestWeaponSetBySkillSlot($a_i_SkillSlot)

	If $GC_UAI_TARGET_MODE_CALL Then
		Local $l_i_Target = $a_i_AgentID
		If $g_i_ForceTarget <> 0 Then $l_i_Target = $g_i_ForceTarget
		If $l_i_Target <> 0 And $l_i_Target <> $l_i_MyID And $l_i_Target <> $g_i_LastCalledTarget Then
			Agent_CallTarget($l_i_Target)
			$g_i_LastCalledTarget = $l_i_Target
		EndIf
	EndIf

	Skill_UseSkill($a_i_SkillSlot, $a_i_AgentID)

	Local $l_i_Special = UAI_GetStaticSkillInfo($a_i_SkillSlot, $GC_UAI_STATIC_SKILL_Special)

	Local $l_f_AggroRangeSq = $a_f_AggroRange * $a_f_AggroRange
	Local $l_h_CastStart = TimerInit()
	Do
		If TimerDiff($l_h_CastStart) > 5000 Then ExitLoop

		Sleep(128)
	
		Local $l_b_TargetIsDead = Agent_GetAgentInfo($a_i_AgentID, "IsDead")
		Local $l_b_CancelCast = (($l_b_TargetIsDead And $l_i_Special <> $GC_I_SKILL_SPECIAL_FLAG_RESURRECTION) _
			Or (Not $l_b_TargetIsDead And $l_i_Special = $GC_I_SKILL_SPECIAL_FLAG_RESURRECTION))

		If $l_b_CancelCast Then
			Core_ControlAction($GC_I_CONTROL_ACTION_CANCEL_ACTION)
			ExitLoop
		EndIf

		Local $l_f_DistanceSq = Agent_GetDistanceSq($a_i_AgentID)
		If $l_f_DistanceSq > $l_f_AggroRangeSq Then ExitLoop
	Until (Not UAI_GetIsCasting()) Or Agent_GetAgentInfo(-2, "IsKnockedDown")
EndFunc   ;==>UAI_UseSkillEx

; Drop bundle if player has Item Spell effect and can cast (skill is recharged)
Func UAI_DropBundle($a_f_AggroRange = 1320)
	For $l_i_Slot = 1 To 8
		; Check if skill is an Item Spell
		Local $l_i_Type = UAI_GetStaticSkillInfo($l_i_Slot, $GC_UAI_STATIC_SKILL_SkillType)
		If $l_i_Type <> $GC_I_SKILL_TYPE_ITEM_SPELL Then ContinueLoop

		; Get skill ID to check if player has the effect
		Local $l_i_SkillID = UAI_GetStaticSkillInfo($l_i_Slot, $GC_UAI_STATIC_SKILL_SkillID)
		If $l_i_SkillID = 0 Then ContinueLoop

		; Check if player has the Item Spell effect (holding the ashes)
		If Not UAI_PlayerHasEffect($l_i_SkillID) Then ContinueLoop

		; Check if skill is recharged (can drop bundle)
		If UAI_CanUse($l_i_Slot) Then
			$g_i_BestTarget = Call($g_as_BestTargetCache[$l_i_Slot], $a_f_AggroRange)
			If $g_i_ForceTarget <> 0 And UAI_GetAgentInfoByID($g_i_BestTarget, $GC_UAI_AGENT_Allegiance) = $GC_I_ALLEGIANCE_ENEMY Then
				$g_i_BestTarget = $g_i_ForceTarget
			EndIf
			If $g_i_BestTarget = 0 Then ContinueLoop
			If Not UAI_Filter_IsNotAvoided($g_i_BestTarget) Then ContinueLoop

			$g_b_CanUseSkill = Call($g_as_CanUseCache[$l_i_Slot])

			If $g_b_CanUseSkill = True And Agent_GetDistance($g_i_BestTarget) < $a_f_AggroRange Then
				UAI_UseSkillEx($l_i_Slot, $g_i_BestTarget)
				If Cache_FormChangeBuild($l_i_Slot) Then $g_b_SkillChanged = True
				UAI_UpdateCache($a_f_AggroRange)
			EndIf
		EndIf

		; Check if skill is not recharged (but can drop bundle)
		If UAI_CanDrop($l_i_Slot) Then
			Core_ControlAction($GC_I_CONTROL_ACTION_DROP_ITEM)
			Return
		EndIf
	Next
EndFunc   ;==>UAI_DropBundle
