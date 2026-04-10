// Tree Sapling — Dendor Content
// Planted by druids and skilled farmers using tree seeds.
// Grows through 4 stages with proper watering:
//   Stage 1 (SAPLING):     small seedling sprite, needs water
//   Stage 2 (SHRUB):       shrub sprite, needs water
//   Stage 3 (YOUNG_TREE):  young tree sprite, removes soil below, standalone
//   Stage 4:               spawns the final tree structure, qdels self

#define TREESAP_STAGE_SAPLING 1
#define TREESAP_STAGE_SHRUB   2
#define TREESAP_STAGE_YOUNG   3

#define TREESAP_WATER_MAX    200
#define TREESAP_STAGE_TIME   360  // seconds per stage (6 minutes)
#define TREESAP_YOUNG_TIME   240  // seconds for young-tree stage (4 minutes)
#define TREESAP_WATER_DRAIN  0.5  // water units lost per second (~6.7 min to dry)
#define TREESAP_DEATH_TICKS  60   // negative-progress seconds before dying

/obj/structure/tree_sapling
	name = "tree sapling"
	desc = "A tender sapling bedded in mounded soil. It needs regular watering to take root."
	anchored = TRUE
	density = FALSE
	opacity = FALSE
	max_integrity = 20
	resistance_flags = FLAMMABLE
	icon = 'icons/obj/flora/ausflora.dmi'
	icon_state = "palebush_2"
	layer = OBJ_LAYER

	var/stage = TREESAP_STAGE_SAPLING
	var/growth_progress = 0   // seconds accumulated toward next stage
	var/water = TREESAP_WATER_MAX
	var/dead = FALSE

	// What tree to spawn when fully grown
	var/tree_final_type = /obj/structure/flora/newtree

	// Per-stage icon data (stage 1 uses own icon/icon_state)
	var/stage2_icon  = 'icons/obj/flora/ausflora.dmi'
	var/stage2_state = "sunnybush_1"
	var/stage3_icon  = 'icons/roguetown/misc/foliagetall.dmi'
	var/stage3_state = "t12"
	var/dead_icon    = 'icons/roguetown/misc/crops.dmi'
	var/dead_state   = "lemon3"
	// pixel_x applied when becoming a young tree
	var/stage3_pixel_x = -16

/obj/structure/tree_sapling/Initialize(mapload)
	. = ..()
	START_PROCESSING(SSprocessing, src)

/obj/structure/tree_sapling/Destroy()
	STOP_PROCESSING(SSprocessing, src)
	return ..()

/obj/structure/tree_sapling/process(dt)
	if(dead)
		return

	if(stage <= TREESAP_STAGE_SHRUB)
		if(water > 0)
			water = max(0, water - TREESAP_WATER_DRAIN * dt)
			growth_progress += dt
		else
			growth_progress -= dt * 2
			if(growth_progress <= -TREESAP_DEATH_TICKS)
				wither_and_die()
				return
	else
		growth_progress += dt

	var/stage_time = (stage == TREESAP_STAGE_YOUNG) ? TREESAP_YOUNG_TIME : TREESAP_STAGE_TIME
	if(growth_progress >= stage_time)
		advance_stage()

/obj/structure/tree_sapling/proc/wither_and_die()
	STOP_PROCESSING(SSprocessing, src)
	dead = TRUE
	name = "withered sapling"
	density = FALSE
	opacity = FALSE
	pixel_x = 0
	icon = dead_icon
	icon_state = dead_state
	visible_message(span_warning("[src] withers and dies from lack of water."))

/obj/structure/tree_sapling/proc/advance_stage()
	growth_progress = 0
	stage++
	switch(stage)
		if(TREESAP_STAGE_SHRUB)
			icon = stage2_icon
			icon_state = stage2_state
		if(TREESAP_STAGE_YOUNG)
			// Uproot any soil below — the tree is taking over
			var/turf/T = get_turf(src)
			for(var/obj/structure/soil/S in T)
				qdel(S)
			icon = stage3_icon
			icon_state = stage3_state
			density = TRUE
			opacity = TRUE
			pixel_x = stage3_pixel_x
		if(4)
			spawn_final_tree()

/obj/structure/tree_sapling/proc/spawn_final_tree()
	new tree_final_type(get_turf(src))
	qdel(src)

/obj/structure/tree_sapling/examine(mob/user)
	. = ..()
	if(dead)
		. += span_warning("It has withered and died. Shovel it out to clear the spot.")
		return
	switch(stage)
		if(TREESAP_STAGE_SAPLING)
			. += span_info("A young seedling just beginning to sprout.")
		if(TREESAP_STAGE_SHRUB)
			. += span_info("A small shrub growing steadily.")
		if(TREESAP_STAGE_YOUNG)
			. += span_notice("A young tree still taking root. It should grow on its own now.")
	if(stage <= TREESAP_STAGE_SHRUB)
		. += span_info("Water: [round(water / TREESAP_WATER_MAX * 100)]%")

/obj/structure/tree_sapling/attackby(obj/item/I, mob/living/user, params)
	// Watering (stages 1-2 only)
	if(istype(I, /obj/item/reagent_containers) && stage <= TREESAP_STAGE_SHRUB && !dead)
		var/obj/item/reagent_containers/RC = I
		if(water >= TREESAP_WATER_MAX)
			to_chat(user, span_notice("The sapling is already well-watered."))
			return
		var/water_amt = RC.reagents.get_reagent_amount(/datum/reagent/water)
		var/holy_amt  = RC.reagents.get_reagent_amount(/datum/reagent/water/holywater)
		var/total = water_amt + holy_amt
		if(total < 1)
			to_chat(user, span_warning("[RC] doesn't have any water in it."))
			return
		RC.reagents.remove_reagent(/datum/reagent/water, water_amt)
		RC.reagents.remove_reagent(/datum/reagent/water/holywater, holy_amt)
		// Each unit of liquid water = 10 sapling water points
		water = min(TREESAP_WATER_MAX, water + total * 10)
		to_chat(user, span_notice("I water [src]."))
		return

	// Shovelling out
	if(istype(I, /obj/item/rogueweapon/shovel))
		to_chat(user, span_notice("I begin uprooting [src]..."))
		if(do_after(user, 3 SECONDS, target = src))
			to_chat(user, span_notice("I remove [src]."))
			qdel(src)
		return

	return ..()

//==============================================================================
// Subtypes
//==============================================================================

/obj/structure/tree_sapling/pine
	name = "pine sapling"
	desc = "A tender pine sapling. Keep it watered and it will grow into a tall pine tree."
	icon_state = "palebush_3"
	stage2_state = "pointybush_1"
	stage3_state = "t11"
	dead_state = "apple3"
	tree_final_type = /obj/structure/flora/roguetree/pine

/obj/structure/tree_sapling/sakura
	name = "sakura sapling"
	desc = "A tender cherry-blossom sapling. Water it faithfully and it will reward you with clouds of pink bloom."
	icon_state = "palebush_1"
	stage2_state = "pinkbush"
	stage3_state = "t10"
	dead_state = "apple3"
	tree_final_type = /obj/structure/flora/sakura
