/obj/mecha/working/ripley
	desc = "Autonomous Power Loader Unit. The workhorse of the exosuit world."
	name = "APLU \"Ripley\""
	icon_state = "ripley"
	step_in = 4
	max_temperature = 20000
	health = 200
	wreckage = /obj/effect/decal/mecha_wreckage/ripley
	var/list/cargo = new
	var/cargo_capacity = 15
	var/obj/structure/ore_box/ore_box //to save on locate()
	var/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/hydraulic_clamp

/*
/obj/mecha/working/ripley/New()
	..()
	return
*/

/obj/mecha/working/ripley/firefighter
	desc = "Standard APLU chassis, refitted with additional thermal protection and cistern."
	name = "APLU \"Firefighter\""
	icon_state = "firefighter"
	max_temperature = 65000
	health = 250
	lights_power = 8
	damage_absorption = list("fire"=0.5,"bullet"=0.8,"bomb"=0.5)
	wreckage = /obj/effect/decal/mecha_wreckage/ripley/firefighter

/obj/mecha/working/ripley/deathripley
	desc = "OH SHIT IT'S THE DEATHSQUAD WE'RE ALL GONNA DIE"
	name = "DEATH-RIPLEY"
	icon_state = "deathripley"
	step_in = 2
	opacity = 0
	lights_power = 60
	wreckage = /obj/effect/decal/mecha_wreckage/ripley/deathripley
	step_energy_drain = 0

/obj/mecha/working/ripley/deathripley/New()
	..()
	var/obj/item/mecha_parts/mecha_equipment/ME = new /obj/item/mecha_parts/mecha_equipment/tool/safety_clamp
	ME.attach(src)
	return

/obj/mecha/working/ripley/mining
	desc = "An old, dusty mining ripley."
	name = "APLU \"Miner\""

/obj/mecha/working/ripley/mining/New()
	..()
	//Attach drill
	if(prob(25)) //Possible diamond drill... Feeling lucky?
		var/obj/item/mecha_parts/mecha_equipment/tool/drill/diamonddrill/D = new /obj/item/mecha_parts/mecha_equipment/tool/drill/diamonddrill
		D.attach(src)
	else
		var/obj/item/mecha_parts/mecha_equipment/tool/drill/D = new /obj/item/mecha_parts/mecha_equipment/tool/drill
		D.attach(src)

	//Attach hydraulic clamp
	var/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/HC = new /obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp
	HC.attach(src)
	src.hydraulic_clamp = HC

	//Deletes the beacon so it can't be found easily
	for(var/obj/item/mecha_parts/mecha_tracking/B in src.contents)
		qdel (B)
		B = null
		src.tracking = null

/obj/mecha/working/ripley/Exit(atom/movable/O)
	if(O in cargo)
		return 0
	return ..()

/obj/mecha/working/ripley/Topic(href, href_list)
	..()
	if(href_list["drop_from_cargo"])
		var/obj/O = locate(href_list["drop_from_cargo"])
		if(O && O in src.cargo)
			src.occupant_message("<span class='notice'>You unload [O].</span>")
			O.forceMove(get_turf(src))
			src.cargo -= O
			if (ore_box == O)
				ore_box = locate(/obj/structure/ore_box) in cargo //i'll fix this later
			src.log_message("Unloaded [O]. Cargo compartment capacity: [cargo_capacity - src.cargo.len]")
	return



/obj/mecha/working/ripley/get_stats_part()
	var/output = ..()
	output += "<b>Cargo Compartment Contents:</b><div style=\"margin-left: 15px;\">"
	if(src.cargo.len)
		for(var/obj/O in src.cargo)
			output += "<a href='?src=\ref[src];drop_from_cargo=\ref[O]'>Unload</a> : [O]<br>"
	else
		output += "Nothing"
	output += "</div>"
	return output

/obj/mecha/working/ripley/empty_bad_contents()
	for(var/obj/O in src)
		if(O in cargo) //mom's spaghetti
			continue
		if(!is_type_in_list(O,mech_parts))
			O.loc = src.loc
	return

/obj/mecha/working/ripley/Destroy()
	for(var/mob/M in src)
		if(M==src.occupant)
			continue
		M.loc = get_turf(src)
		M.loc.Entered(M)
		step_rand(M)
	for(var/atom/movable/A in src.cargo)
		A.loc = get_turf(src)
		var/turf/T = get_turf(A)
		if(T)
			T.Entered(A)
		step_rand(A)
	..()
	return
