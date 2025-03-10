var/datum/controller/gameticker/ticker

/datum/controller/gameticker
	var/remaining_time = 0
	var/const/restart_timeout = 60 SECONDS //Right now, this is padded out by the end credit's audio starting time (at the time of writing this, 10 seconds)
	var/current_state = GAME_STATE_PREGAME
	var/gamestart_time = -1 //In seconds. Set by ourselves in setup()
	var/shuttledocked_time = -1 //In seconds. Set by emergency_shuttle/proc/shuttle_phase()
	var/gameend_time = -1 //In seconds. Set by ourselves in process()

	var/pregame_timeleft = 0
	var/delay_end = 0	//if set to nonzero, the round will not restart on its own

	var/hide_mode = 0
	var/datum/gamemode/mode = null
	var/event_time = null
	var/event = 0

	var/list/achievements = list()

	var/login_music			// music played in pregame lobby

	var/list/datum/mind/minds = list()//The people in the game. Used for objective tracking.

	var/Bible_icon_state	// icon_state the OFFICIAL chaplain has chosen for his bible
	var/Bible_item_state	// item_state the OFFICIAL chaplain has chosen for his bible
	var/Bible_name			// name of the bible
	var/Bible_deity_name = "Space Jesus" 	// Default deity
	var/datum/religion/chap_rel 			// Official religion of chappy
	var/list/datum/religion/religions = list() // Religion(s) in the game

	var/list/runescape_skulls = list() // Keeping track of the runescape skulls that appear over mobs when enabled

	var/random_players = 0 	// if set to nonzero, ALL players who latejoin or declare-ready join will have random appearances/genders

	var/hardcore_mode = 0	//If set to nonzero, hardcore mode is enabled (current hardcore mode features: damage from hunger)
							//Use the hardcore_mode_on macro - if(hardcore_mode_on) to_chat(user,"You're hardcore!")
	var/datum/rune_controller/rune_controller

	var/triai = 0 //Global holder for Triumvirate

	var/explosion_in_progress
	var/station_was_nuked
	var/no_life_on_station
	var/revolutionary_victory //If on, Castle can be voted if the conditions are right

	var/list/datum/role/antag_types = list() // Associative list of all the antag types in the round (List[id] = roleNumber1) //Seems to be totally unused?

	// Hack
	var/obj/machinery/media/jukebox/superjuke/thematic/theme = null

	// Tag mode!
	var/tag_mode_enabled = FALSE


#define LOBBY_TICKING 1
#define LOBBY_TICKING_RESTARTED 2
/datum/controller/gameticker/proc/pregame()
	var/path = "sound/music/login/"
	if(Holiday == APRIL_FOOLS_DAY)
		path = "sound/music/aprilfools/"
	else if(SNOW_THEME)
		path = "sound/music/xmas/"
	else if(map.nameShort == "castle")
		path = "sound/music/castle/"
	var/list/filenames = flist(path)
	for(var/filename in filenames)
		if(copytext(filename, length(filename)) == "/")
			filenames -= filename
	if (map.nameShort == "lamprey")
		login_music = file("sound/music/lampreytheme.ogg")
	else if (map.nameShort == "dorf")
		login_music = file("sound/music/b12_combined_start.ogg")
	else
		login_music = file("[path][pick(filenames)]")

	send2maindiscord("**Server is loaded** and in pre-game lobby at `[config.server? "byond://[config.server]" : "byond://[world.address]:[world.port]"]`", TRUE)

	do
#ifdef GAMETICKER_LOBBY_DURATION
		var/delay_timetotal = GAMETICKER_LOBBY_DURATION
#else
		var/delay_timetotal = DEFAULT_LOBBY_TIME
#endif
		pregame_timeleft = world.timeofday + delay_timetotal
		to_chat(world, "<B><span class='notice'>Welcome to the pre-game lobby!</span></B>")
		to_chat(world, "Please, setup your character and select ready. Game will start in [(pregame_timeleft - world.timeofday) / 10] seconds.")
		while(current_state <= GAME_STATE_PREGAME)
			for(var/i=0, i<10, i++)
				sleep(1)
				vote.process()
				watchdog.check_for_update()
				//if(watchdog.waiting)
//					to_chat(world, "<span class='notice'>Server update detected, restarting momentarily.</span>")
					//watchdog.signal_ready()
					//return
			if (world.timeofday < (863800 -  delay_timetotal) &&  pregame_timeleft > 863950) // having a remaining time > the max of time of day is bad....
				pregame_timeleft -= 864000
			if(!going && !remaining_time)
				remaining_time = pregame_timeleft - world.timeofday
			if(going == LOBBY_TICKING_RESTARTED)
				pregame_timeleft = world.timeofday + remaining_time
				going = LOBBY_TICKING
				remaining_time = 0

			if(going && world.timeofday >= pregame_timeleft)
				current_state = GAME_STATE_SETTING_UP
	while (!setup())
#undef LOBBY_TICKING
#undef LOBBY_TICKING_RESTARTED

/datum/controller/gameticker/proc/IsThematic(var/playlist)
	if(!theme)
		return 0
	if(theme.playlist_id == playlist)
		return 1
	return 0

/datum/controller/gameticker/proc/StartThematic(var/playlist)
	if(!theme)
		theme = new(locate(1,1,map.zCentcomm))
	theme.playlist_id=playlist
	theme.playing=1
	theme.update_music()
	theme.update_icon()

/datum/controller/gameticker/proc/StopThematic()
	if(!theme)
		return
	theme.playing=0
	theme.update_music()
	theme.update_icon()


/datum/controller/gameticker/proc/setup()
	//Create and announce mode
	if(master_mode=="secret")
		src.hide_mode = 1
	var/list/datum/gamemode/runnable_modes
	if((master_mode=="random"))
		runnable_modes = config.get_runnable_modes()
		if (runnable_modes.len==0)
			current_state = GAME_STATE_PREGAME
			to_chat(world, "<B>Unable to choose playable game mode.</B> Reverting to pre-game lobby.")
			return 0
		if(secret_force_mode != "secret")
			var/datum/gamemode/M = config.pick_mode(secret_force_mode)
			if(M.can_start())
				src.mode = config.pick_mode(secret_force_mode)
		job_master.ResetOccupations()
		if(!src.mode)
			src.mode = pickweight(runnable_modes)
		if(src.mode)
			var/mtype = src.mode.type
			src.mode = new mtype
	else if (master_mode=="secret")
		mode = config.pick_mode("Dynamic Mode") //Huzzah
	else
		src.mode = config.pick_mode(master_mode)

	//log_startup_progress("gameticker.mode is [src.mode.name].")
	src.mode = new mode.type
	if (!src.mode.can_start())
		to_chat(world, "<B>Unable to start [mode.name].</B> Not enough players, [mode.minimum_player_count] players needed. Reverting to pre-game lobby.")
		del(mode)
		current_state = GAME_STATE_PREGAME
		job_master.ResetOccupations()
		return 0

	//Configure mode and assign player to special mode stuff
	job_master.DivideOccupations() //Distribute jobs

	gamestart_time = world.time / 10

	init_mind_ui()
	init_PDAgames_leaderboard()
	create_characters() //Create player characters and transfer them
	collect_minds()

	var/can_continue = src.mode.Setup()//Setup special modes
	if(!can_continue)
		current_state = GAME_STATE_PREGAME
		to_chat(world, "<B>Error setting up [master_mode].</B> Reverting to pre-game lobby.")
		log_admin("The gamemode setup for [mode.name] errored out.")
		world.log << "The gamemode setup for [mode.name] errored out."
		del(mode)
		job_master.ResetOccupations()
		return 0

	if(hide_mode)
		var/list/modes = new
		for (var/datum/gamemode/M in runnable_modes)
			modes+=M.name
		modes = sortList(modes)
		if(Holiday == APRIL_FOOLS_DAY)
			to_chat(world, "<B>The current game mode is - [pick("Chivalry","Crab Battle","Bay Transfer","Dwarf Fortress","Ian Says","Admins Funhouse","Meteor","Xenoarchaeology Appreciation","Clowns versus [pick("Mimes","Assistants","the Universe")]","Dino wars","Malcolm in the Middle","Six hours of extended where one person with all the access refuses to call the shuttle while everyone else goes braindead","Monkey Study","Nations","Nations by Hasbro","High roleplay Extended","DarkRP","Babies Day out","Ians Day out","Shortstaffed medical")]!</B>")
		else
			to_chat(world, "<B>The current game mode is - Secret!</B>")
			to_chat(world, "<B>Possibilities:</B> [english_list(modes)]")

	equip_characters()

	for(var/mob/living/carbon/human/player in player_list)
		switch(player.mind.assigned_role)
			if("MODE","Mobile MMI","Trader")
				//No injection
			else
				player.update_icons()
				data_core.manifest_inject(player)

	current_state = GAME_STATE_PLAYING

	// Update new player panels so they say join instead of ready up.
	for(var/mob/new_player/player in player_list)
		player.new_player_panel_proc()


#if UNIT_TESTS_AUTORUN
	run_unit_tests()
#endif

	spawn(0)//Forking here so we dont have to wait for this to finish
		mode.PostSetup()
		//Cleanup some stuff
		for(var/obj/effect/landmark/start/S in landmarks_list)
			//Deleting Startpoints but we need the ai point to AI-ize people later and the Trader point to throw new ones
			if (S.name != "AI" && S.name != "Trader")
				qdel(S)
		var/list/obj/effect/landmark/spacepod/random/L = list()
		for(var/obj/effect/landmark/spacepod/random/SS in landmarks_list)
			if(istype(SS))
				L += SS
		if(L.len)
			var/obj/effect/landmark/spacepod/random/S = pick(L)
			new /obj/spacepod/random(S.loc)
			for(var/obj in L)
				if(istype(obj, /obj/effect/landmark/spacepod/random))
					qdel(obj)

		to_chat(world, "<span class='notice'><B>Enjoy the game!</B></span>")

		send2maindiscord("**The game has started**")

//		world << sound('sound/AI/welcome.ogg')// Skie //Out with the old, in with the new. - N3X15

		if(!config.shut_up_automatic_diagnostic_and_announcement_system)
			var/welcome_sentence=list('sound/AI/vox_login.ogg')
			welcome_sentence += pick(
				'sound/AI/vox_reminder1.ogg',
				'sound/AI/vox_reminder2.ogg',
				'sound/AI/vox_reminder3.ogg',
				'sound/AI/vox_reminder4.ogg',
				'sound/AI/vox_reminder5.ogg',
				'sound/AI/vox_reminder6.ogg',
				'sound/AI/vox_reminder7.ogg',
				'sound/AI/vox_reminder8.ogg',
				'sound/AI/vox_reminder9.ogg',
				'sound/AI/vox_reminder10.ogg',
				'sound/AI/vox_reminder11.ogg',
				'sound/AI/vox_reminder12.ogg',
				'sound/AI/vox_reminder13.ogg',
				'sound/AI/vox_reminder14.ogg',
				'sound/AI/vox_reminder15.ogg')
			for(var/sound in welcome_sentence)
				play_vox_sound(sound,map.zMainStation,null)
		//Holiday Round-start stuff	~Carn
		Holiday_Game_Start()
		//mode.Clean_Antags()
		create_random_orders(3) //Populate the order system so cargo has something to do
	//start_events() //handles random events and space dust.
	//new random event system is handled from the MC.

	if(0 == admins.len)
		send2adminirc("Round has started with no admins online.")
		send2admindiscord("**Round has started with no admins online.**", TRUE)

	Master.RoundStart()

	if(config.sql_enabled)
		spawn(3000)
		statistic_cycle() // Polls population totals regularly and stores them in an SQL DB -- TLE

	stat_collection.round_start_time = world.realtime

	wageSetup()
	post_roundstart()
	return 1

/datum/controller/gameticker
	//station_explosion used to be a variable for every mob's hud. Which was a waste!
	//Now we have a general cinematic centrally held within the gameticker....far more efficient!
	var/obj/abstract/screen/cinematic = null

	//Plus it provides an easy way to make cinematics for other events. Just use this as a template :)
/datum/controller/gameticker/proc/station_explosion_cinematic(var/station_missed=0, var/override = null)
	if( cinematic )
		return	//already a cinematic in progress!

	for (var/datum/html_interface/hi in html_interfaces)
		hi.closeAll()

	//initialise our cinematic screen object
	cinematic = new(src)
	cinematic.icon = 'icons/effects/station_explosion.dmi'
	cinematic.icon_state = "station_intact"
	cinematic.plane = HUD_PLANE
	cinematic.mouse_opacity = 0
	cinematic.screen_loc = "1,0"

	for(var/mob/M in player_list)
		if(M.client)
			M.client.screen += cinematic	//show every client the cinematic
		if (istype(M,/mob/living/carbon/human))
			var/mob/living/carbon/human/C = M
			C.apply_radiation(rand(50, 250),RAD_EXTERNAL)

	//Now animate the cinematic
	switch(station_missed)
		if(1)	//nuke was nearby but (mostly) missed
			if( mode && !override )
				override = mode.name
			switch( override )
				if("nuclear emergency") //Nuke wasn't on station when it blew up
					flick("intro_nuke",cinematic)
					sleep(35)
					world << sound('sound/effects/explosionfar.ogg')
					flick("station_intact_fade_red",cinematic)
					cinematic.icon_state = "summary_nukefail"
				else
					flick("intro_nuke",cinematic)
					sleep(35)
					world << sound('sound/effects/explosionfar.ogg')
					//flick("end",cinematic)


		if(2)	//nuke was nowhere nearby	//TODO: a really distant explosion animation
			world << sound('sound/effects/explosionfar.ogg')
		else	//station was destroyed
			if( mode && !override )
				override = mode.name
			switch( override )
				if("nuclear emergency") //Nuke Ops successfully bombed the station
					flick("intro_nuke",cinematic)
					sleep(35)
					flick("station_explode_fade_red",cinematic)
					world << sound('sound/effects/explosionfar.ogg')
					cinematic.icon_state = "summary_nukewin"
				if("AI malfunction") //Malf (screen,explosion,summary)
					flick("intro_malf",cinematic)
					sleep(76)
					flick("station_explode_fade_red",cinematic)
					world << sound('sound/effects/explosionfar.ogg')
					cinematic.icon_state = "summary_malf"
				else //Station nuked (nuke,explosion,summary)
					flick("intro_nuke",cinematic)
					sleep(35)
					flick("station_explode_fade_red", cinematic)
					world << sound('sound/effects/explosionfar.ogg')
					cinematic.icon_state = "summary_selfdes"

	if(cinematic)
		qdel(cinematic)		//end the cinematic

/datum/controller/gameticker/proc/station_nolife_cinematic(var/override = null)
	if( cinematic )
		return	//already a cinematic in progress!

	for (var/datum/html_interface/hi in html_interfaces)
		hi.closeAll()

	//initialise our cinematic screen object
	cinematic = new(src)
	cinematic.icon = 'icons/effects/station_explosion.dmi'
	cinematic.icon_state = "station_nolife"
	cinematic.plane = HUD_PLANE
	cinematic.mouse_opacity = 0
	cinematic.screen_loc = "1,0"

	//actually turn everything off
	power_failure(0)

	//If its actually the end of the round, wait for it to end.
	//Otherwise if its a verb it will continue on afterwards.
	sleep(300)

	if(cinematic)
		qdel(cinematic)		//end the cinematic

	no_life_on_station = TRUE

/datum/controller/gameticker/proc/create_characters()
	for(var/mob/new_player/player in player_list)
		if(player.ready && player.mind)
			if(player.mind.assigned_role=="AI" || player.mind.assigned_role=="Cyborg" || player.mind.assigned_role=="Mobile MMI")
				log_admin("([player.ckey]) started the game as a [player.mind.assigned_role].")
				player.create_roundstart_silicon(player.mind.assigned_role)
			else if(!player.mind.assigned_role)
				continue
			else
				var/mob/living/carbon/human/new_character = player.create_character(0)
				new_character.DormantGenes(20,10,0,0) // 20% chance of getting a dormant bad gene, in which case they also get 10% chance of getting a dormant good gene
				qdel(player)


/datum/controller/gameticker/proc/collect_minds()
	for(var/mob/living/player in player_list)
		if(player.mind)
			ticker.minds += player.mind

/datum/controller/gameticker/proc/equip_characters()
	var/captainless=1
	for(var/mob/living/carbon/human/player in player_list)
		if(player && player.mind && player.mind.assigned_role)
			if(player.mind.assigned_role == "Captain")
				captainless=0
			if(player.mind.assigned_role != "MODE")
				job_master.EquipRank(player, player.mind.assigned_role, 0)
				EquipCustomItems(player)
			player.apeify()
	if(captainless)
		for(var/mob/M in player_list)
			if(!istype(M,/mob/new_player))
				to_chat(M, "Captainship not forced on anyone.")

	for(var/mob/M in player_list)
		if(!istype(M,/mob/new_player))
			M.store_position()//updates the players' origin_ vars so they retain their location when the round starts.

/datum/controller/gameticker/proc/process()
	if(current_state != GAME_STATE_PLAYING)
		return 0

	mode.process()

	if(world.time > nanocoins_lastchange)
		nanocoins_lastchange = world.time + rand(3000,15000)
		nanocoins_rates = (rand(1,30))/10

	//runescape skull updates
	if (runescape_skull_display)
		for (var/entry in runescape_skulls)
			var/datum/runescape_skull_data/the_data = runescape_skulls[entry]
			the_data.process()

	/*emergency_shuttle.process()*/
	watchdog.check_for_update()

	var/force_round_end=0

	// If server's empty, force round end.
	if(watchdog.waiting && player_list.len == 0)
		force_round_end=1

	var/mode_finished = mode.check_finished() || (emergency_shuttle.location == 2 && emergency_shuttle.alert == 1) || force_round_end
	if(!explosion_in_progress && mode_finished)
		current_state = GAME_STATE_FINISHED

		spawn
			declare_completion()
			gameend_time = world.time / 10
			if(!vote.map_paths)
				vote.initiate_vote("map","The Server", popup = 1)
				var/options = jointext(vote.choices, " ")
				feedback_set("map vote choices", options)

			if (station_was_nuked)
				feedback_set_details("end_proper","nuke")
				if(!delay_end && !watchdog.waiting)
					to_chat(world, "<span class='notice'><B>Rebooting due to destruction of station in [restart_timeout/10] seconds</B></span>")
			else
				feedback_set_details("end_proper","\proper completion")
				if(!delay_end && !watchdog.waiting)
					to_chat(world, "<span class='notice'><B>Restarting in [restart_timeout/10] seconds</B></span>")

			end_credits.on_round_end()

			if(blackbox)
				if(player_list.len)
					spawn(restart_timeout + 1)
						blackbox.save_all_data_to_sql()
				else
					blackbox.save_all_data_to_sql()

			stat_collection.Process()

			if (watchdog.waiting)
				to_chat(world, "<span class='notice'><B>Server will shut down for an automatic update in [player_list.len ? "[(restart_timeout/10)] seconds." : "a few seconds."]</B></span>")
				if(player_list.len)
					sleep(restart_timeout) //waiting for a mapvote to end
				if(!delay_end)
					watchdog.signal_ready()
				else
					to_chat(world, "<span class='notice'><B>An admin has delayed the round end</B></span>")
					delay_end = 2
			else if(!delay_end)
				sleep(restart_timeout)
				if(!delay_end)
					CallHook("Reboot",list())
					world.Reboot()
				else
					to_chat(world, "<span class='notice'><B>An admin has delayed the round end</B></span>")
					delay_end = 2
			else
				to_chat(world, "<span class='notice'><B>An admin has delayed the round end</B></span>")
				delay_end = 2
	return 1

/datum/controller/gameticker/proc/init_PDAgames_leaderboard()
	init_snake_leaderboard()
	init_minesweeper_leaderboard()

/datum/controller/gameticker/proc/init_snake_leaderboard()
	for(var/x=1;x<=PDA_APP_SNAKEII_MAXSPEED;x++)
		snake_station_highscores += x
		snake_station_highscores[x] = list()
		snake_best_players += x
		snake_best_players[x] = list()
		var/list/templist1 = snake_station_highscores[x]
		var/list/templist2 = snake_best_players[x]
		for(var/y=1;y<=PDA_APP_SNAKEII_MAXLABYRINTH;y++)
			templist1 += y
			templist1[y] = 0
			templist2 += y
			templist2[y] = "none"

/datum/controller/gameticker/proc/init_minesweeper_leaderboard()
	minesweeper_station_highscores["beginner"] = 999
	minesweeper_station_highscores["intermediate"] = 999
	minesweeper_station_highscores["expert"] = 999
	minesweeper_best_players["beginner"] = "none"
	minesweeper_best_players["intermediate"] = "none"
	minesweeper_best_players["expert"] = "none"

/datum/controller/gameticker/proc/declare_completion()
	if(!ooc_allowed)
		to_chat(world, "<B>The OOC channel has been automatically re-enabled!</B>")
		ooc_allowed = TRUE
	score.main()
	return 1

/datum/controller/gameticker/proc/bomberman_declare_completion()
	var/icon/bomberhead = icon('icons/obj/clothing/hats.dmi', "bomberman")
	var/icon/bronze = icon('icons/obj/bomberman.dmi', "bronze")
	var/icon/silver = icon('icons/obj/bomberman.dmi', "silver")
	var/icon/gold = icon('icons/obj/bomberman.dmi', "gold")
	var/icon/platinum = icon('icons/obj/bomberman.dmi', "platinum")

	var/list/bronze_tier = list()
	for (var/mob/living/carbon/M in player_list)
		if(locate(/obj/item/weapon/bomberman/) in M)
			bronze_tier += M
	var/list/silver_tier = list()
	for (var/mob/M in bronze_tier)
		if(M.z == map.zCentcomm)
			silver_tier += M
			bronze_tier -= M
	var/list/gold_tier = list()
	for (var/mob/M in silver_tier)
		var/turf/T = get_turf(M)
		if(istype(T.loc, /area/shuttle/escape/centcom))
			gold_tier += M
			silver_tier -= M
	var/list/platinum_tier = list()
	for (var/mob/living/carbon/human/M in gold_tier)
		if(istype(M.wear_suit, /obj/item/clothing/suit/space/bomberman) && istype(M.head, /obj/item/clothing/head/helmet/space/bomberman))
			var/obj/item/clothing/suit/space/bomberman/C1 = M.wear_suit
			var/obj/item/clothing/head/helmet/space/bomberman/C2 = M.head
			if(C1.never_removed && C2.never_removed)
				platinum_tier += M
				gold_tier -= M

	var/list/special_tier = list()
	for (var/mob/living/silicon/robot/mommi/M in player_list)
		if(istype(M.head_state, /obj/item/clothing/head/helmet/space/bomberman) && istype(M.tool_state, /obj/item/weapon/bomberman/))
			special_tier += M

	var/text = {"<img class='icon' src='data:image/png;base64,[iconsouth2base64(bomberhead)]'> <font size=5><b>Bomberman Mode Results</b></font> <img class='icon' src='data:image/png;base64,[iconsouth2base64(bomberhead)]'>"}
	if(!platinum_tier.len && !gold_tier.len && !silver_tier.len && !bronze_tier.len)
		text += "<br><span class='danger'>DRAW!</span>"
	if(platinum_tier.len)
		text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(platinum)]'> <b>Platinum Trophy</b> (never removed his clothes, kept his bomb dispenser until the end, and escaped on the shuttle):"}
		for (var/mob/M in platinum_tier)
			var/icon/flat = getFlatIcon(M, SOUTH, 1, 1)
			text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(flat)]'> <b>[M.key]</b> as <b>[M.real_name]</b>"}
	if(gold_tier.len)
		text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(gold)]'> <b>Gold Trophy</b> (kept his bomb dispenser until the end, and escaped on the shuttle):"}
		for (var/mob/M in gold_tier)
			var/icon/flat = getFlatIcon(M, SOUTH, 1, 1)
			text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(flat)]'> <b>[M.key]</b> as <b>[M.real_name]</b>"}
	if(silver_tier.len)
		text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(silver)]'> <b>Silver Trophy</b> (kept his bomb dispenser until the end, and escaped in a pod):"}
		for (var/mob/M in silver_tier)
			var/icon/flat = getFlatIcon(M, SOUTH, 1, 1)
			text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(flat)]'> <b>[M.key]</b> as <b>[M.real_name]</b>"}
	if(bronze_tier.len)
		text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(bronze)]'> <b>Bronze Trophy</b> (kept his bomb dispenser until the end):"}
		for (var/mob/M in bronze_tier)
			var/icon/flat = getFlatIcon(M, SOUTH, 1, 1)
			text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(flat)]'> <b>[M.key]</b> as <b>[M.real_name]</b>"}
	if(special_tier.len)
		text += "<br><b>Special Mention</b> to those adorable MoMMis:"
		for (var/mob/M in special_tier)
			var/icon/flat = getFlatIcon(M, SOUTH, 1, 1)
			text += {"<br><img class='icon' src='data:image/png;base64,[iconsouth2base64(flat)]'> <b>[M.key]</b> as <b>[M.name]</b>"}

	return text

/datum/controller/gameticker/proc/achievement_declare_completion()
	if(!ticker.achievements.len)
		return
	var/text = "<br><FONT size = 5><b>Additionally, the following players earned achievements:</b></FONT>"
	for(var/datum/achievement/achievement in ticker.achievements)
		text += {"<br>[bicon(achievement.item)] <b>[achievement.ckey]</b> as <b>[achievement.mob_name]</b> won <b>[achievement.award_name]</b>, <b>[achievement.award_desc]!</b>"}
	return text

/datum/controller/gameticker/proc/get_all_heads()
	var/list/heads = list()
	for(var/mob/player in mob_list)
		if(player.mind && (player.mind.assigned_role in command_positions))
			heads += player.mind
	return heads

/datum/controller/gameticker/proc/get_assigned_head_roles()
	var/list/roles = list()
	for(var/mob/player in mob_list)
		if(player.mind && (player.mind.assigned_role in command_positions))
			roles += player.mind.assigned_role
	return roles

/datum/controller/gameticker/proc/post_roundstart()
	//Handle all the cyborg syncing
	var/list/active_ais = active_ais()
	if(active_ais.len)
		for(var/mob/living/silicon/robot/R in cyborg_list)
			if(!R.connected_ai)
				R.connect_AI(select_active_ai_with_fewest_borgs())
				to_chat(R, R.connected_ai?"<b>You have synchronized with an AI. Their name will be stated shortly. Other AIs can be ignored.</b>":"<b>You are not synchronized with an AI, and therefore are not required to heed the instructions of any unless you are synced to them.</b>")
			R.lawsync()

	//Toggle lightswitches and lamps on in occupied departments
	var/discrete_areas = list()
	for(var/mob/living/carbon/human/H in player_list)
		var/area/A = get_area(H)
		if(!(A in discrete_areas)) //We've already added their department
			discrete_areas += get_department_areas(H)
	CHECK_TICK
	for(var/area/DA in discrete_areas)
		for(var/obj/machinery/light_switch/LS in DA)
			LS.toggle_switch(1)
			break
		for(var/obj/item/device/flashlight/lamp/L in DA)
			L.toggle_onoff(1)
	CHECK_TICK
	//Toggle lights without lightswitches
	//with better area organization, a lot of this headache can be limited
	for(var/area/A in areas - discrete_areas)
		if(!A.requires_power || !A.haslightswitch)
			for(var/obj/machinery/light/L in A)
				L.seton(1)
	CHECK_TICK

// -- Tag mode!

/datum/controller/gameticker/proc/tag_mode(var/mob/user)
	tag_mode_enabled = TRUE
	to_chat(world, "<h1>Tag mode enabled!<h1>")
	to_chat(world, "<span class='notice'>Tag mode is a 'gamemode' about a changeling clown infiltrated in a station populated by Mimes. His goal is to destroy it. Any mime killing the clown will in turn become the changeling.</span>")
	to_chat(world, "<span class='notice'>The game ends when all mimes are dead, or when the shuttle is called.</span>")
	to_chat(world, "<span class='notice'>Have fun!</span>")

	// This is /datum/forced_ruleset thing. This shit exists ONLY for pre-roundstart rulesets. Yes. This is a thing.
	var/datum/forced_ruleset/tag_mode = new
	tag_mode.name = "Tag mode"
	tag_mode.calledBy = "[key_name(user)]"
	forced_roundstart_ruleset += tag_mode
	dynamic_forced_extended = TRUE

/datum/controller/gameticker/proc/cancel_tag_mode(var/mob/user)
	tag_mode_enabled = FALSE
	to_chat(world, "<h1>Tag mode has been cancelled.<h1>")
	dynamic_forced_extended = FALSE
	forced_roundstart_ruleset = list()

/world/proc/has_round_started()
	return ticker && ticker.current_state >= GAME_STATE_PLAYING
