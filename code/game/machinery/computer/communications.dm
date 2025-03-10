
#define COMM_SCREEN_MAIN		1
#define COMM_SCREEN_STAT		2
#define COMM_SCREEN_MESSAGES	3
#define COMM_SCREEN_SECLEVEL	4
#define COMM_SCREEN_ERT			5
#define COMM_SCREEN_SHUTTLE_LOG 6

#define UNAUTH 0
#define AUTH_HEAD 1
#define AUTH_CAPT 2

#define MEDICAL_SUPPLIES_DEFCON "medical"
#define ENGINEERING_SUPPLIES_DEFCON "engineering"
#define WEAPONS_SUPPLIES_DEFCON "weapons"

var/shuttle_call/shuttle_calls[0]
var/global/ports_open = TRUE

#define SHUTTLE_RECALL  -1
#define SHUTTLE_CALL     1
#define SHUTTLE_TRANSFER 2

var/list/shuttle_log = list()

/shuttle_call
	var/direction=0
	var/who=""
	var/ckey=""
	var/turf/from=null
	var/where=""
	var/when
	var/eta=null

/shuttle_call/New(var/mob/user,var/obj/machinery/computer/communications/computer,var/dir)
	direction=dir
	if(user)
		who="[user]"
		ckey="[user.key]"
	if(computer)
		where="[computer]"
		from=get_turf(computer)
	when=worldtime2text()
	if(dir==SHUTTLE_RECALL)
		var/timeleft=emergency_shuttle.timeleft()
		eta="[timeleft / 60 % 60]:[add_zero(num2text(timeleft % 60), 2)]"

// The communications computer
/obj/machinery/computer/communications
	name = "Communications Console"
	desc = "A console that is used for various important Command functions."
	icon_state = "comm"
	req_access = list(access_heads)
	circuit = "/obj/item/weapon/circuitboard/communications"
	var/prints_intercept = 1
	var/authenticated = UNAUTH //1 = normal login, 2 = emagged or had access_captain, 0 = logged out. Gremlins can set to 1 or 0.
	var/list/messagetitle = list()
	var/list/messagetext = list()
	var/currmsg = 0
	var/aicurrmsg = 0
	var/menu_state = COMM_SCREEN_MAIN
	var/ai_menu_state = COMM_SCREEN_MAIN
	var/message_cooldown = 0
	var/centcomm_message_cooldown = 0
	var/tmp_alertlevel = 0
	hack_abilities = list(
		/datum/malfhack_ability/toggle/disable,
		/datum/malfhack_ability/oneuse/overload_quiet,
		/datum/malfhack_ability/fake_announcement,
		/datum/malfhack_ability/oneuse/emag,
	)

	// Blob stuff
	var/defcon_1_enabled = FALSE
	var/last_transfer_time = -1 // Game mechanics

	var/last_shipment_time = "Unknown" // IC message on the NanoUI console
	var/next_shipment_time = "Unknown"
	var/blob_transfer_delay = 5 MINUTES

	var/status_display_freq = "1435"
	var/stat_msg1
	var/stat_msg2
	var/display_type="blank"

	light_color = LIGHT_COLOR_BLUE

/obj/machinery/computer/communications/Topic(href, href_list)
	if(..(href, href_list))
		return

	if(href_list["close"])
		if(usr.machine == src)
			usr.unset_machine()
		return 1

	if (!(src.z in list(map.zMainStation,map.zCentcomm)))
		to_chat(usr, "<span class='danger'>Unable to establish a connection: </span>You're too far away from the station!")
		return

	usr.set_machine(src)

	if(!href_list["operation"])
		return
	switch(href_list["operation"])
		// main interface
		if("main")
			setMenuState(usr,COMM_SCREEN_MAIN)
		if("login")
			var/mob/M = usr
			if(allowed(M))
				authenticated = AUTH_HEAD
				if(access_captain in M.GetAccess())
					authenticated = AUTH_CAPT
			if(emagged) //Login regardless if you have an ID
				authenticated = AUTH_CAPT
		if("logout")
			authenticated = UNAUTH
			setMenuState(usr,COMM_SCREEN_MAIN)

		// Blob stuff
		if ("request_supplies")
			if (!defcon_1_enabled) // Href exploits
				return FALSE
			if (world.time < last_transfer_time + blob_transfer_delay)
				say("Unable to send more supplies at this time. Telecrystals stil re-aligning.")
				alert_noise("buzz")
				return FALSE
			if (!href_list["supplies"]) // No supplies to send, schade
				return FALSE

			last_transfer_time = world.time
			last_shipment_time = worldtime2text()
			next_shipment_time = add_minutes(last_shipment_time, 5)
			send_supplies(href_list["supplies"])

		// ALART LAVUL
		if("changeseclevel")
			setMenuState(usr,COMM_SCREEN_SECLEVEL)

		if("newalertlevel")
			if(issilicon(usr) && !is_malf_owner(usr))
				return
			tmp_alertlevel = text2num(href_list["level"])
			var/mob/M = usr
			if (allowed(M) || emagged)
				if(isAdminGhost(usr) || (access_heads in M.GetAccess()) || emagged) //Let heads change the alert level. Works while emagged
					var/old_level = security_level
					if(!tmp_alertlevel)
						tmp_alertlevel = SEC_LEVEL_GREEN
					if(tmp_alertlevel < SEC_LEVEL_GREEN)
						tmp_alertlevel = SEC_LEVEL_GREEN
					if(tmp_alertlevel > SEC_LEVEL_BLUE)
						tmp_alertlevel = SEC_LEVEL_BLUE //Cannot engage delta with this
					set_security_level(tmp_alertlevel)
					if(security_level != old_level)
						//Only notify the admins if an actual change happened
						log_game("[key_name(usr)] has changed the security level to [get_security_level()].")
						message_admins("[key_name_admin(usr)] has changed the security level to [get_security_level()].")
						switch(security_level)
							if(SEC_LEVEL_GREEN)
								feedback_inc("alert_comms_green",1)
							if(SEC_LEVEL_BLUE)
								feedback_inc("alert_comms_blue",1)
					tmp_alertlevel = 0
				else
					to_chat(usr, "You are not authorized to do this.")
					tmp_alertlevel = 0
				setMenuState(usr,COMM_SCREEN_MAIN)
			else
				to_chat(usr, "You need to have a valid ID.")

		if("announce")
			if(authenticated==AUTH_CAPT && !(issilicon(usr) && !is_malf_owner(usr)))
				if(message_cooldown)
					return
				var/input = stripped_message(usr, "Please choose a message to announce to the station crew.", "Priority Announcement")
				if(message_cooldown || !input || (!usr.Adjacent(src) && !issilicon(usr)))
					return
				captain_announce(input)//This should really tell who is, IE HoP, CE, HoS, RD, Captain
				var/turf/T = get_turf(usr)
				log_say("[key_name(usr)] (@[T.x],[T.y],[T.z]) has made a Comms Console announcement: [input]")
				message_admins("[key_name_admin(usr)] has made a Comms Console announcement.", 1)
				message_cooldown = 1
				spawn(600)//One minute cooldown
					message_cooldown = 0

		if("emergency_screen")
			if(!authenticated)
				to_chat(usr, "<span class='warning'>You do not have clearance to use this function.</span>")
				return
			setMenuState(usr,COMM_SCREEN_ERT)
			return
		if("request_emergency_team")
			if(!map.linked_to_centcomm)
				to_chat(usr, "<span class='danger'>Error: No connection can be made to central command.</span>")
				return
			if(menu_state != COMM_SCREEN_ERT)
				return //Not on the right screen.
			if ((!(ticker) || emergency_shuttle.location))
				to_chat(usr, "<span class='warning'>Warning: The evac shuttle has already arrived.</span>")
				return

			if(!universe.OnShuttleCall(usr))
				to_chat(usr, "<span class='notice'>\The [src.name] cannot establish a bluespace connection.</span>")
				return

			if(sentStrikeTeams(TEAM_DEATHSQUAD))
				to_chat(usr, "<span class='warning'>PKI AUTH ERROR: SERVER REPORTS BLACKLISTED COMMUNICATION KEY PLEASE CONTACT SERVICE TECHNICIAN</span>")
				return

			if(sentStrikeTeams(TEAM_ERT))
				to_chat(usr, "<span class='notice'>Central Command has already dispatched a Response Team to [station_name()]</span>")
				return

			if(!(get_security_level() in list("red", "delta")))
				to_chat(usr, "<span class='notice'>The station must be in an emergency to request a Response Team.</span>")
				return
			if(!authenticated || issilicon(usr))
				to_chat(usr, "<span class='warning'>\The [src.name]'s screen flashes, \"Access Denied\".</span>")
				return

			var/response = alert(usr,"Are you sure you want to request a response team?", "ERT Request", "Yes", "No")
			if(response != "Yes")
				return
			var/ert_reason = stripped_input(usr, "Please input the reason for calling an Emergency Response Team. This may be all the information they get before arriving at the station.", "Response Team Justification")
			if(!ert_reason)
				to_chat(usr, "<span class='warning'>You are required to give a reason to call an ERT.</span>")
				return
			if(!usr.Adjacent(src) || usr.incapacitated())
				return
			var/datum/striketeam/ert/response_team = new()
			response_team.trigger_strike(usr,ert_reason,TRUE)
			log_game("[key_name(usr)] has called an ERT with reason: [ert_reason]")
			message_admins("[key_name_admin(usr)] has called an ERT with reason: [ert_reason]")
			setMenuState(usr,COMM_SCREEN_MAIN)
			return

		if("callshuttle")
			if(authenticated || isAdminGhost(usr))
				if(!map.linked_to_centcomm && !isAdminGhost(usr)) //We don't need a connection if we're an admin
					to_chat(usr, "<span class='danger'>Error: No connection can be made to central command.</span>")
					return
				var/justification = stripped_input(usr, "Please input a concise justification for the shuttle call. Note that failure to properly justify a shuttle call may lead to recall or termination.", "Nanotrasen Anti-Comdom Systems")
				if(!justification || !(usr in view(1,src)))
					return
				var/response = alert("Are you sure you wish to call the shuttle?", "Confirm", "Yes", "Cancel")
				if(response == "Yes")
					call_shuttle_proc(usr, justification)
					if(emergency_shuttle.online)
						post_status("shuttle")
			setMenuState(usr,COMM_SCREEN_MAIN)
		if("cancelshuttle")
			if(!map.linked_to_centcomm && !isAdminGhost(usr))
				to_chat(usr, "<span class='danger'>Error: No connection can be made to central command.</span>")
				return
			if(issilicon(usr))
				return
			if(authenticated || isAdminGhost(usr))
				var/response = alert("Are you sure you wish to recall the shuttle?", "Confirm", "Yes", "No")
				if(response == "Yes")
					recall_shuttle(usr)
					if(!isobserver(usr))
						shuttle_log += "\[[worldtime2text()]] Recalled from [get_area(usr)] ([usr.x-WORLD_X_OFFSET[usr.z]], [usr.y-WORLD_Y_OFFSET[usr.z]], [usr.z])."
					if(emergency_shuttle.online)
						post_status("shuttle")
			setMenuState(usr,COMM_SCREEN_MAIN)
		if("messagelist")
			src.currmsg = 0
			if(href_list["msgid"])
				setCurrentMessage(usr, text2num(href_list["msgid"]))
			setMenuState(usr,COMM_SCREEN_MESSAGES)
		if("delmessage")
			if(href_list["msgid"])
				src.currmsg = text2num(href_list["msgid"])
			var/response = alert("Are you sure you wish to delete this message?", "Confirm", "Yes", "No")
			if(response == "Yes")
				if(src.currmsg)
					var/id = getCurrentMessage()
					var/title = src.messagetitle[id]
					var/text  = src.messagetext[id]
					src.messagetitle.Remove(title)
					src.messagetext.Remove(text)
					if(currmsg==id)
						currmsg=0
					if(aicurrmsg==id)
						aicurrmsg=0
			setMenuState(usr,COMM_SCREEN_MESSAGES)

		if("status")
			setMenuState(usr,COMM_SCREEN_STAT)

		// Status display stuff
		if("setstat")
			display_type=href_list["statdisp"]
			switch(display_type)
				if("message")
					post_status("message", stat_msg1, stat_msg2)
				if("alert")
					post_status("alert", href_list["alert"])
					display_type = href_list["alert"]
				else
					post_status(href_list["statdisp"])
			setMenuState(usr,COMM_SCREEN_STAT)

		if("setmsg1")
			stat_msg1 = reject_bad_text(trim(copytext(sanitize(input("Line 1", "Enter Message Text", stat_msg1) as text|null), 1, 40)), 40)
			setMenuState(usr,COMM_SCREEN_STAT)
		if("setmsg2")
			stat_msg2 = reject_bad_text(trim(copytext(sanitize(input("Line 2", "Enter Message Text", stat_msg2) as text|null), 1, 40)), 40)
			setMenuState(usr,COMM_SCREEN_STAT)

		// OMG CENTCOMM LETTERHEAD
		if("MessageCentcomm")
			if(authenticated==AUTH_CAPT)
				if(!map.linked_to_centcomm)
					to_chat(usr, "<span class='danger'>Error: No connection can be made to central command.</span>")
					return
				if(centcomm_message_cooldown)
					to_chat(usr, "<span class='warning'>Arrays recycling.  Please stand by for a few seconds.</span>")
					return
				var/input = stripped_input(usr, "Please choose a message to transmit to Centcomm via quantum entanglement.  Please be aware that this process is very expensive, and abuse will lead to... termination.  Transmission does not guarantee a response. There is a 30 second delay before you may send another message, be clear, full and concise.", "To abort, send an empty message.", "")
				if(!input || (!usr.Adjacent(src) && !issilicon(usr)))
					return
				Centcomm_announce(input, usr)
				to_chat(usr, "<span class='notice'>Message transmitted.</span>")
				var/turf/T = get_turf(usr)
				log_say("[key_name(usr)] (@[T.x],[T.y],[T.z]) has sent a bluespace message to Centcomm: [input]")
				centcomm_message_cooldown = 1
				spawn(300)//30 seconds cooldown
					centcomm_message_cooldown = 0
			setMenuState(usr,COMM_SCREEN_MAIN)


		// OMG SYNDICATE ...LETTERHEAD
		if("MessageSyndicate")
			if(src.authenticated==AUTH_CAPT && emagged)
				if(!map.linked_to_centcomm)
					to_chat(usr, "<span class='danger'>Error: No connection can be made to \[ABNORMAL ROUTING CORDINATES\] .</span>")
					return
				if(centcomm_message_cooldown)
					to_chat(usr, "<span class='warning'>Arrays recycling.  Please stand by for a few seconds.</span>")
					return
				var/input = stripped_input(usr, "Please choose a message to transmit to \[ABNORMAL ROUTING CORDINATES\] via quantum entanglement.  Please be aware that this process is very expensive, and abuse will lead to... termination. Transmission does not guarantee a response. There is a 30 second delay before you may send another message, be clear, full and concise.", "To abort, send an empty message.", "")
				if(!input || !(usr in view(1,src)))
					return
				Syndicate_announce(input, usr)
				to_chat(usr, "<span class='notice'>Message transmitted.</span>")
				var/turf/T = get_turf(usr)
				log_say("[key_name(usr)] (@[T.x],[T.y],[T.z]) has sent a bluespace message to the syndicate: [input]")
				centcomm_message_cooldown = 1
				spawn(300)//30 seconds cooldown
					centcomm_message_cooldown = 0
			setMenuState(usr,COMM_SCREEN_MAIN)

		if("RestoreBackup")
			to_chat(usr, "Backup routing data restored!")
			src.emagged = 0
			setMenuState(usr,COMM_SCREEN_MAIN)
			update_icon()

		if("SetPortRestriction")

			if(issilicon(usr) && !is_malf_owner(usr))
				return
			var/mob/M = usr
			var/obj/item/weapon/card/id/I = M.get_id_card()
			if (I || isAdminGhost(usr) || issilicon(usr))
				if(isAdminGhost(usr) || issilicon(usr) || (access_hos in I.access) || ((access_heads in I.access) && security_level >= SEC_LEVEL_RED))
					if(ports_open)
						var/reason = stripped_input(usr, "Please input a concise justification for port closure. This reason will be announced to the crew, as well as transmitted to the trader shuttle.", "Nanotrasen Anti-Comdom Systems")
						if(!reason)
							to_chat(usr, "You must provide some reason for closing the docking port.")
							return
						if(!(usr in view(1,src)) && !issilicon(usr))
							return
						command_alert("The trading port is now on lockdown. Third party traders are no longer free to dock their shuttles with the station. Reason given:\n\n[reason]", "Trading Port - Now on Lockdown", 1)
						world << sound('sound/AI/trading_port_closed.ogg')
						log_game("[key_name(usr)] closed the port to traders for reason: [reason].")
						message_admins("[key_name_admin(usr)] closed the port to traders for reason: [reason].")
						if(trade_shuttle.current_port.areaname == "NanoTrasen Station")
							var/obj/machinery/computer/shuttle_control/C = trade_shuttle.control_consoles[1] //There should be exactly one
							if(C)
								trade_shuttle.travel_to(pick(trade_shuttle.docking_ports - trade_shuttle.current_port),C) //Just send it; this has all relevant checks
						trade_shuttle.remove_dock(/obj/docking_port/destination/trade/station)
						trade_shuttle.notify_port_toggled(reason)
						ports_open = FALSE
						return
					if(!ports_open)
						var/response = alert(usr,"Are you sure you wish to re-open the station to traders?", "Port Opening", "Yes", "No")
						if(response != "Yes")
							return
						command_alert("The trading port lockdown has been lifted. Third party traders are now free to dock their shuttles with the station.", "Trading Port - Open for Business", 1)
						world << sound('sound/AI/trading_port_open.ogg')
						log_game("[key_name(usr)] opened the port to traders.")
						message_admins("[key_name_admin(usr)] opened the port to traders.")
						trade_shuttle.add_dock(/obj/docking_port/destination/trade/station)
						trade_shuttle.notify_port_toggled()
						ports_open = TRUE
						return
				else
					to_chat(usr, "<span class='warning'>This action requires either a red alert or head of security authorization.</span>")
			else
				to_chat(usr, "<span class='warning'>You must wear an ID for this function.</span>")
		if("ViewShuttleLog")
			setMenuState(usr, COMM_SCREEN_SHUTTLE_LOG)
	return 1

/obj/machinery/computer/communications/attack_paw(var/mob/user as mob)
	return src.attack_hand(user)


/obj/machinery/computer/communications/attack_hand(var/mob/user as mob)
	if(..(user))
		return

	if (!(src.z in list(map.zMainStation, map.zCentcomm)))
		to_chat(user, "<span class='danger'>Unable to establish a connection: </span>You're too far away from the station!")
		return

	ui_interact(user)



/obj/machinery/computer/communications/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open=NANOUI_FOCUS)
	if(user.stat && !isAdminGhost(user))
		return

	// this is the data which will be sent to the ui
	var/data[0]
	data["is_ai"] = issilicon(user)
	data["menu_state"] = data["is_ai"] ? ai_menu_state : menu_state
	data["emagged"] = emagged
	data["authenticated"] = (isAdminGhost(user) ? AUTH_CAPT : authenticated)
	var/current_screen = getMenuState(usr)
	if(current_screen == COMM_SCREEN_SHUTTLE_LOG)
		data["shuttle_log"] = list()
		for(var/entry in shuttle_log)
			data["shuttle_log"] += list(list("text" = entry))
	data["screen"] = current_screen

	data["stat_display"] = list(
		"type"=display_type,
		"line_1"=(stat_msg1 ? stat_msg1 : "-----"),
		"line_2"=(stat_msg2 ? stat_msg2 : "-----"),
		"presets"=list(
			list("name"="blank",    "label"="Clear",       "desc"="Blank slate"),
			list("name"="shuttle",  "label"="Shuttle ETA", "desc"="Display how much time is left."),
			list("name"="message",  "label"="Message",     "desc"="A custom message.")
		),
		"alerts"=list(
			list("alert"="default",   "label"="Nanotrasen",  "desc"="Oh god."),
			list("alert"="redalert",  "label"="Red Alert",   "desc"="Nothing to do with communists."),
			list("alert"="lockdown",  "label"="Lockdown",    "desc"="Let everyone know they're on lockdown."),
			list("alert"="biohazard", "label"="Biohazard",   "desc"="Great for virus outbreaks and parties."),
		)
	)
	data["security_level"] = security_level
	data["str_security_level"] = get_security_level()
	data["levels"] = list(
		list("id"=SEC_LEVEL_GREEN, "name"="Green"),
		list("id"=SEC_LEVEL_BLUE,  "name"="Blue"),
		//SEC_LEVEL_RED = list("name"="Red"),
	)
	data["portopen"] = ports_open
	data["ert_sent"] = sentStrikeTeams(TEAM_ERT)

	var/msg_data[0]
	for(var/i=1;i<=src.messagetext.len;i++)
		var/cur_msg[0]
		cur_msg["title"]=messagetitle[i]
		cur_msg["body"]=messagetext[i]
		cur_msg["id"] = i
		msg_data += list(cur_msg)
	data["messages"] = msg_data
	data["current_message"] = data["is_ai"] ? aicurrmsg : currmsg

	var/shuttle[0]
	shuttle["on"]=emergency_shuttle.online
	if (emergency_shuttle.online && emergency_shuttle.location==0)
		var/timeleft=emergency_shuttle.timeleft()
		shuttle["eta"]="[timeleft / 60 % 60]:[add_zero(num2text(timeleft % 60), 2)]"
	shuttle["pos"] = emergency_shuttle.location
	shuttle["can_recall"]=!(recall_time_limit && world.time >= recall_time_limit)

	data["shuttle"]=shuttle

	data["defcon_1_enabled"] = defcon_1_enabled
	data["last_shipment_time"] = last_shipment_time
	data["next_shipment_time"] = next_shipment_time

	// update the ui if it exists, returns null if no ui is passed/found
	ui = nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		// the ui does not exist, so we'll create a new() one
        // for a list of parameters and their descriptions see the code docs in \code\\modules\nano\nanoui.dm
		ui = new(user, src, ui_key, "comm_console.tmpl", "Communications Console", 400, 500)
		// when the ui is first opened this is the data it will use
		ui.set_initial_data(data)
		// open the new ui window
		ui.open()
		// auto update every Master Controller tick
		ui.set_auto_update(1)

/obj/machinery/computer/communications/emag_act(mob/user as mob)
	if(!emagged)
		emagged = 1
		if(user)
			to_chat(user, "Syndicate routing data uploaded!")
		spark(src)
		authenticated = AUTH_CAPT
		setMenuState(usr,COMM_SCREEN_MAIN)
		update_icon()
		return 1
	return


/obj/machinery/computer/communications/update_icon()
	..()
	var/initial_icon = initial(icon_state)
	icon_state = "[emagged ? "[initial_icon]-emag" : "[initial_icon]"]"
	if(stat & BROKEN)
		icon_state = "[initial_icon]b"
	else if(stat & (FORCEDISABLE|NOPOWER))
		icon_state = "[initial_icon]0"


/obj/machinery/computer/communications/proc/setCurrentMessage(var/mob/user,var/value)
	if(issilicon(user))
		aicurrmsg=value
	else
		currmsg=value

/obj/machinery/computer/communications/proc/getCurrentMessage(var/mob/user)
	if(issilicon(user))
		return aicurrmsg
	else
		return currmsg

/obj/machinery/computer/communications/proc/setMenuState(var/mob/user,var/value)
	if(issilicon(user))
		ai_menu_state=value
	else
		menu_state=value

/obj/machinery/computer/communications/proc/getMenuState(var/mob/user)
	if(issilicon(user))
		return ai_menu_state
	else
		return menu_state

/proc/enable_prison_shuttle(var/mob/user)
	for(var/obj/machinery/computer/prison_shuttle/PS in machines)
		PS.allowedtocall = !(PS.allowedtocall)

/proc/call_shuttle_proc(var/mob/user, var/justification)
	if ((!(ticker) || emergency_shuttle.location))
		return

	if(!universe.OnShuttleCall(user))
		return
	if(!map.linked_to_centcomm)
		to_chat(usr, "<span class='danger'>Error: No connection can be made to central command .</span>")
		return

	//if(sent_strike_team == 1)
	//	to_chat(user, "Centcom will not allow the shuttle to be called. Consider all contracts terminated.")
	//	return

	if(emergency_shuttle.shutdown)
		to_chat(user, "The emergency shuttle has been disabled.")
		return

	if(ticker && (world.time / 10 < ticker.gamestart_time + SHUTTLEGRACEPERIOD)) // Five minute grace period to let the game get going without lolmetagaming. -- TLE
		to_chat(user, "The emergency shuttle is refueling. Please wait another [round((ticker.gamestart_time + SHUTTLEGRACEPERIOD - world.time / 10) / 60, 1)] minute\s before trying again.")
		return

	if(emergency_shuttle.direction == -1)
		to_chat(user, "The emergency shuttle may not be called while returning to CentCom.")
		return

	if(emergency_shuttle.online)
		to_chat(user, "The emergency shuttle is already on its way.")
		return

	if(ticker.mode.name == "blob")
		to_chat(user, "Under directive 7-10, [station_name()] is quarantined until further notice.")
		return

	emergency_shuttle.incall()
	if(!justification)
		justification = "#??!7E/_1$*/ARR-CON�FAIL!!*$^?" //Can happen for reasons, let's deal with it IC
	if(!isobserver(user))
		shuttle_log += "\[[worldtime2text()]] Called from [get_area(user)] ([user.x-WORLD_X_OFFSET[user.z]], [user.y-WORLD_Y_OFFSET[user.z]], [user.z])."
	log_game("[key_name(user)] has called the shuttle. Justification given : '[justification]'")
	message_admins("[key_name_admin(user)] has called the shuttle. Justification given : '[justification]'.", 1)
	var/datum/command_alert/emergency_shuttle_called/CA = new /datum/command_alert/emergency_shuttle_called
	CA.justification = justification
	command_alert(CA)

	return 1

/proc/init_shift_change(var/mob/user, var/force = 0)
	if (!ticker)
		return
	if (emergency_shuttle.direction == -1 && vote.winner ==  "Initiate Crew Transfer")
		emergency_shuttle.setdirection(1)
		emergency_shuttle.settimeleft(10)
		var/reason = pick("is arriving ahead of schedule", "hit the turbo", "has engaged nitro afterburners")
		captain_announce("The emergency shuttle reversed and [reason]. It will arrive in [emergency_shuttle.timeleft()] seconds.")
		return
	if(emergency_shuttle.direction == -1)
		to_chat(user, "The shuttle may not be called while returning to CentCom.")
		return
	if (emergency_shuttle.online && vote.winner ==  "Initiate Crew Transfer")
		if(10 < emergency_shuttle.timeleft())
			var/reason = pick("is arriving ahead of schedule", "hit the turbo", "has engaged nitro afterburners")
			emergency_shuttle.settimeleft(10)
			captain_announce("The emergency shuttle [reason]. It will arrive in [emergency_shuttle.timeleft()] seconds.")
		return
	if(emergency_shuttle.online)
		to_chat(user, "The shuttle is already on its way.")
		return

	// if force is 0, some things may stop the shuttle call
	if(!force)
		if(!universe.OnShuttleCall(user))
			return

		if(emergency_shuttle.deny_shuttle)
			to_chat(user, "Centcom does not currently have a shuttle available in your sector. Please try again later.")
			return

		//if(sent_strike_team == 1)
		//	to_chat(user, "Centcom will not allow the shuttle to be called. Consider all contracts terminated.")
		//	return

		if(world.time < 54000) // 30 minute grace period to let the game get going
			to_chat(user, "The shuttle is refueling. Please wait another [round((54000-world.time)/600)] minutes before trying again.")//may need to change "/600"

			return

		if(ticker.mode.name == "revolution" || ticker.mode.name == "AI malfunction" || ticker.mode.name == "sandbox")
			//New version pretends to call the shuttle but cause the shuttle to return after a random duration.
			emergency_shuttle.fake_recall = rand(300,500)

		if(ticker.mode.name == "blob" || ticker.mode.name == "epidemic")
			to_chat(user, "Under directive 7-10, [station_name()] is quarantined until further notice.")
			return

	emergency_shuttle.shuttlealert(1)
	emergency_shuttle.incall()
	log_game("[key_name(user)] has called the shuttle.")
	message_admins("[key_name_admin(user)] has called the shuttle - [formatJumpTo(user)].", 1)
	captain_announce("A crew transfer has been initiated. The shuttle has been called. It will arrive in [round(emergency_shuttle.timeleft()/60)] minutes.")

	return

/proc/recall_shuttle(var/mob/user)
	if ((!( ticker ) || emergency_shuttle.location || emergency_shuttle.direction == 0 || emergency_shuttle.timeleft() < 300))
		return
	if( ticker.mode.name == "blob" || ticker.mode.name == "meteor")
		return

	if(emergency_shuttle.direction != -1 && emergency_shuttle.online) //check that shuttle isn't already heading to centcomm
		emergency_shuttle.recall()
		var/datum/gamemode/dynamic/dynamic_mode = ticker.mode
		if (istype(dynamic_mode))
			dynamic_mode.update_stillborn_rulesets()
		log_game("[key_name(user)] has recalled the shuttle.")
		message_admins("[key_name_admin(user)] has recalled the shuttle - [formatJumpTo(user)].", 1)
	return

/obj/machinery/computer/communications/proc/post_status(var/command, var/data1, var/data2)


	var/datum/radio_frequency/frequency = radio_controller.return_frequency(1435)

	if(!frequency)
		return

	var/datum/signal/status_signal = new /datum/signal
	status_signal.source = src
	status_signal.transmission_method = 1
	status_signal.data["command"] = command

	switch(command)
		if("message")
			status_signal.data["msg1"] = data1
			status_signal.data["msg2"] = data2
			log_admin("STATUS: [src.fingerprintslast] set status screen message with [src]: [data1] [data2]")
			//message_admins("STATUS: [user] set status screen with [PDA]. Message: [data1] [data2]")
		if("alert")
			status_signal.data["picture_state"] = data1

	frequency.post_signal(src, status_signal)

/obj/machinery/computer/communications/npc_tamper_act(mob/living/user)
	if(!authenticated)
		if(prob(20)) //20% chance to log in
			authenticated = AUTH_HEAD

	else //Already logged in
		if(prob(50)) //50% chance to log off
			authenticated = UNAUTH
		else if(isgremlin(user)) //make a hilarious public message
			var/mob/living/simple_animal/hostile/gremlin/G = user
			var/result = G.generate_markov_chain()

			if(result)
				captain_announce(result)
				log_say("[key_name(usr)] ([formatJumpTo(get_turf(G))]) has made a captain announcement: [result]")
				message_admins("[key_name_admin(G)] has made a captain announcement.", 1)

/obj/machinery/computer/communications/Destroy()

	for(var/obj/machinery/computer/communications/commconsole in machines)
		if(istype(commconsole.loc,/turf) && commconsole != src && commconsole.z != map.zCentcomm)
			return ..()

	for(var/obj/item/weapon/circuitboard/communications/commboard in communications_circuitboards)
		if((istype(commboard.loc,/turf) || istype(commboard.loc,/obj/item/weapon/storage)) && commboard.z != map.zCentcomm)
			return ..()

	for(var/mob/living/silicon/ai/shuttlecaller in player_list)
		if(!shuttlecaller.stat && shuttlecaller.client && istype(shuttlecaller.loc,/turf) && shuttlecaller.z != map.zCentcomm)
			return ..()

	if(ticker.mode.name == "revolution" || ticker.mode.name == "AI malfunction")
		return ..()

	shuttle_autocall("All the AIs, comm consoles and boards are destroyed")
	..()

// -- Blob defcon 1 things

/obj/machinery/computer/communications/proc/send_supplies(var/supplies)
	// Find a suitable place
	var/true_dir
	for (var/direction in cardinal)
		var/turf/T = get_step(src, dir)
		if (istype(T, /turf/simulated/floor)) // See if it's an empty space
			true_dir = T
			break
	if (!true_dir)
		alert_noise("buzz")
		say("Unable to find suitable place to transfer supplies.")
		return

	var/turf/T_supplies = get_step(src, true_dir)
	// Some sparks
	spark(src, 3)
	spark(T_supplies, 3)

	switch(supplies)
		if (MEDICAL_SUPPLIES_DEFCON)
			new /obj/structure/closet/crate/medical/blob_supplies(T_supplies)
		if (ENGINEERING_SUPPLIES_DEFCON)
			new /obj/structure/closet/crate/engi/blob_supplies(T_supplies)
		if (WEAPONS_SUPPLIES_DEFCON)
			new /obj/structure/closet/crate/basic/blob_weapons(T_supplies)

// -- Blob supplies crates

/obj/structure/closet/crate/medical/blob_supplies
	name = "EMERGENCY MEDICAL SUPPLIES"
	desc = "Not included: field amputations."

/obj/structure/closet/crate/medical/blob_supplies/New()
	. = ..()
	var/list/contains = list(/obj/item/weapon/storage/firstaid/regular,
					/obj/item/weapon/storage/firstaid/fire,
					/obj/item/weapon/storage/firstaid/toxin,
					/obj/item/weapon/storage/firstaid/o2,
					/obj/item/weapon/storage/firstaid/internalbleed,
					/obj/item/weapon/storage/box/autoinjectors,
					/obj/item/weapon/storage/box/antiviral_syringes)
	for (var/item_type in contains)
		new item_type(src)

/obj/structure/closet/crate/engi/blob_supplies
	name = "EMERGENCY ENGINEERING SUPPLIES"
	desc = "Then we will fight it in the dark!"

/obj/structure/closet/crate/engi/blob_supplies/New()
	. = ..()
	var/list/contains = list(/obj/item/stack/sheet/metal/bigstack,
			/obj/item/stack/sheet/glass/glass/bigstack,
			/obj/item/weapon/storage/toolbox/electrical,
			/obj/item/weapon/storage/toolbox/mechanical,
			/obj/item/clothing/gloves/yellow,
			/obj/item/weapon/cell/high,
			/obj/item/weapon/cell/high,
			/obj/item/weapon/cell/high,)
	for (var/item_type in contains)
		new item_type(src)

/obj/structure/closet/crate/basic/blob_weapons
	name = "EMERGENCY WEAPONS SUPPLIES"
	desc = "Rage, rage against the dying of the light."

/obj/structure/closet/crate/basic/blob_weapons/New()
	. = ..()
	var/list/contains = pick(list(/obj/item/weapon/gun/energy/gun,
			/obj/item/weapon/gun/energy/gun,
			/obj/item/weapon/gun/energy/gun),
			list(/obj/item/weapon/gun/energy/gun/nuclear))
	for (var/item_type in contains)
		new item_type(src)

// -- Circuit borads

/obj/item/weapon/circuitboard/communications/New()
	..()
	communications_circuitboards.Add(src)

/obj/item/weapon/circuitboard/communications/Destroy()
	communications_circuitboards.Remove(src)
	for(var/obj/machinery/computer/communications/commconsole in machines)
		if(istype(commconsole.loc,/turf) && commconsole.z != map.zCentcomm)
			return ..()

	for(var/obj/item/weapon/circuitboard/communications/commboard in communications_circuitboards)
		if((istype(commboard.loc,/turf) || istype(commboard.loc,/obj/item/weapon/storage)) && commboard != src && commboard.z != map.zCentcomm)
			return ..()

	for(var/mob/living/silicon/ai/shuttlecaller in player_list)
		if(!shuttlecaller.stat && shuttlecaller.client && istype(shuttlecaller.loc,/turf) && shuttlecaller.z != map.zCentcomm)
			return ..()

	if(ticker.mode.name == "revolution" || ticker.mode.name == "AI malfunction")
		return ..()

	shuttle_autocall("All the AIs, comm consoles and boards are destroyed")

	..()
