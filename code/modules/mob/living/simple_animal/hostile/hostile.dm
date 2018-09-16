/mob/living/simple_animal/hostile
	faction = "hostile"
	var/stance = HOSTILE_STANCE_IDLE	//Used to determine behavior
	var/mob/living/target_mob
	var/attack_same = 0
	var/ranged = 0
	var/rapid = 0
	var/projectiletype
	var/projectilesound
	var/casingtype
	var/move_to_delay = 4 //delay for the automated movement.
	var/attack_delay = DEFAULT_ATTACK_COOLDOWN
	var/list/friends = list()
	var/break_stuff_probability = 10
	stop_automated_movement_when_pulled = 0
	var/destroy_surroundings = 1
	a_intent = I_HURT

	var/shuttletarget = null
	var/enroute = 0

	var/damtype = BRUTE
	var/defense = "melee" //what armor protects against its attacks
	var/clean_up_time = 0
	var/last_found = 0
/mob/living/simple_animal/hostile/Initialize()
	. = ..()
	last_found = world.time
	STOP_PROCESSING(SSmobs, src) //initialize comes with the mob processing on the main SSmobs, so we move it here without shitting on the init code any more than we did with Destroy()
	START_PROCESSING(SSmobslow, src)
//these two procs were established in order to have hostile mobs lag the fuck out of the server when it gets filled. handling them in a different subsystem.
/mob/living/simple_animal/hostile/Destroy() //copypasted 100% from mob.dm so nothing is missed before deleting.
	STOP_PROCESSING(SSmobslow, src)
	GLOB.dead_mob_list_ -= src
	GLOB.living_mob_list_ -= src
	unset_machine()
	QDEL_NULL(hud_used)
	for(var/obj/item/grab/G in grabbed_by)
		qdel(G)
	clear_fullscreen()
	if(client)
		remove_screen_obj_references()
		for(var/atom/movable/AM in client.screen)
			var/obj/screen/screenobj = AM
			if(!istype(screenobj) || !screenobj.globalscreen)
				qdel(screenobj)
		client.screen = list()
	if(mind && mind.current == src)
		spellremove(src)
	ghostize()
	..()
	return QDEL_HINT_HARDDEL

/mob/living/simple_animal/hostile/proc/FindTarget()
	if(!faction) //No faction, no reason to attack anybody.
		return null
	var/atom/T = null
	stop_automated_movement = 0
	for(var/atom/A in ListTargets(10))

		if(A == src)
			continue

		var/atom/F = Found(A)
		if(F)
			T = F
			last_found = world.time
			break

		if(isliving(A))
			var/mob/living/L = A
			if(L.faction == src.faction && !attack_same)
				continue
			else if(weakref(L) in friends)
				continue
			else
				if(!L.stat)
					if (ishuman(L))
						var/mob/living/carbon/human/H = L
						if (H.is_cloaked())
							continue
					stance = HOSTILE_STANCE_ATTACK
					T = L
					last_found = world.time
					break

		else if(istype(A, /obj/mecha)) // Our line of sight stuff was already done in ListTargets().
			var/obj/mecha/M = A
			if (M.occupant)
				stance = HOSTILE_STANCE_ATTACK
				T = M
				last_found = world.time
				break
	return T


/mob/living/simple_animal/hostile/proc/Found(var/atom/A)
	return

/mob/living/simple_animal/hostile/proc/MoveToTarget()
	stop_automated_movement = 1
	if(!target_mob || SA_attackable(target_mob))
		stance = HOSTILE_STANCE_IDLE
	if(target_mob in ListTargets(10))
		if(ranged)
			if(get_dist(src, target_mob) <= 6)
				OpenFire(target_mob)
			else
				walk_to(src, target_mob, 1, move_to_delay)
		else
			stance = HOSTILE_STANCE_ATTACKING
			walk_to(src, target_mob, 1, move_to_delay)

/mob/living/simple_animal/hostile/proc/AttackTarget()
	stop_automated_movement = 1
	if(!target_mob || SA_attackable(target_mob))
		LoseTarget()
		return 0
	if(!(target_mob in ListTargets(10)))
		LostTarget()
		return 0
	if (ishuman(target_mob))
		var/mob/living/carbon/human/H = target_mob
		if (H.is_cloaked())
			LoseTarget()
			return 0
	if(next_move >= world.time)
		return 0
	if(get_dist(src, target_mob) <= 1)	//Attacking
		AttackingTarget()
		return 1

/mob/living/simple_animal/hostile/proc/AttackingTarget()
	setClickCooldown(attack_delay)
	if(!Adjacent(target_mob))
		return
	if(isliving(target_mob))
		var/mob/living/L = target_mob
		L.attack_generic(src,rand(melee_damage_lower,melee_damage_upper),attacktext,damtype,defense)
		return L
	else
		var/obj/M = target_mob
		M.attack_generic(src,rand(melee_damage_lower,melee_damage_upper),attacktext)
		return M

/mob/living/simple_animal/hostile/proc/LoseTarget()
	stance = HOSTILE_STANCE_IDLE
	target_mob = null
	walk(src, 0)

/mob/living/simple_animal/hostile/proc/LostTarget()
	stance = HOSTILE_STANCE_IDLE
	walk(src, 0)


/mob/living/simple_animal/hostile/proc/ListTargets(var/dist = 7)
	var/list/L = view(dist, src)

//	for (var/obj/mecha/M in mechas_list)
//		if (M.z == src.z && get_dist(src, M) <= dist)
//			L += M

	return L

/mob/living/simple_animal/hostile/death(gibbed, deathmessage, show_dead_message)
	..(gibbed, deathmessage, show_dead_message)
	clean_up_time = rand(world.realtime+45 MINUTES, world.realtime+75 MINUTES)
	walk(src, 0)

/mob/living/simple_animal/hostile/Life()
	if(stat && world.realtime > clean_up_time)
		loc = null
		qdel(src)
	if(last_found < world.time - 1 HOUR)
		loc = null
		qdel(src)
	. = ..()
	if(!.)
		walk(src, 0)
		return 0
	if(client)
		return 0
	if(isturf(src.loc) && !src.buckled)
		if(!stat)
			switch(stance)
				if(HOSTILE_STANCE_IDLE)
					target_mob = FindTarget()

				if(HOSTILE_STANCE_ATTACK)
					if(destroy_surroundings)
						DestroySurroundings()
					MoveToTarget()

				if(HOSTILE_STANCE_ATTACKING)
					if(destroy_surroundings)
						DestroySurroundings()
					AttackTarget()
				if(HOSTILE_STANCE_INSIDE) //we aren't inside something so just switch
					stance = HOSTILE_STANCE_IDLE
	else
		if(stance != HOSTILE_STANCE_INSIDE)
			stance = HOSTILE_STANCE_INSIDE
			walk(src,0)
			target_mob = null


/mob/living/simple_animal/hostile/attackby(var/obj/item/O, var/mob/user)
	var/oldhealth = health
	. = ..()
	if(health < oldhealth && !incapacitated(INCAPACITATION_KNOCKOUT))
		target_mob = user
		MoveToTarget()

/mob/living/simple_animal/hostile/attack_hand(mob/living/carbon/human/M)
	. = ..()
	if(M.a_intent == I_HURT && !incapacitated(INCAPACITATION_KNOCKOUT))
		target_mob = M
		MoveToTarget()

/mob/living/simple_animal/hostile/bullet_act(var/obj/item/projectile/Proj)
	var/oldhealth = health
	. = ..()
	if(!target_mob && health < oldhealth && !incapacitated(INCAPACITATION_KNOCKOUT))
		target_mob = Proj.firer
		MoveToTarget()

/mob/living/simple_animal/hostile/proc/OpenFire(target_mob)
	var/target = target_mob
	visible_message("<span class='danger'>\The [src] fires at \the [target]!</span>", 1)

	if(rapid)
		spawn(1)
			Shoot(target, src.loc, src)
			if(casingtype)
				new casingtype(get_turf(src))
		spawn(4)
			Shoot(target, src.loc, src)
			if(casingtype)
				new casingtype(get_turf(src))
		spawn(6)
			Shoot(target, src.loc, src)
			if(casingtype)
				new casingtype(get_turf(src))
	else
		Shoot(target, src.loc, src)
		if(casingtype)
			new casingtype

	stance = HOSTILE_STANCE_IDLE
	target_mob = null
	return


/mob/living/simple_animal/hostile/proc/Shoot(var/target, var/start, var/user, var/bullet = 0)
	if(target == start)
		return

	var/obj/item/projectile/A = new projectiletype(user:loc)
	playsound(user, projectilesound, 100, 1)
	if(!A)	return
	var/def_zone = get_exposed_defense_zone(target)
	A.launch(target, def_zone)

/mob/living/simple_animal/hostile/proc/DestroySurroundings()
	if(prob(break_stuff_probability))
		for(var/dir in GLOB.cardinal) // North, South, East, West
			var/obj/effect/shield/S = locate(/obj/effect/shield, get_step(src, dir))
			if(S && S.gen && S.gen.check_flag(MODEFLAG_NONHUMANS))
				S.attack_generic(src,rand(melee_damage_lower,melee_damage_upper),attacktext)
				return
			for(var/obj/structure/window/obstacle in get_step(src, dir))
				if(obstacle.dir == GLOB.reverse_dir[dir]) // So that windows get smashed in the right order
					obstacle.attack_generic(src,rand(melee_damage_lower,melee_damage_upper),attacktext)
					return
			var/obj/structure/obstacle = locate(/obj/structure, get_step(src, dir))
			if(istype(obstacle, /obj/structure/window) || istype(obstacle, /obj/structure/closet) || istype(obstacle, /obj/structure/table) || istype(obstacle, /obj/structure/grille))
				obstacle.attack_generic(src,rand(melee_damage_lower,melee_damage_upper),attacktext)
