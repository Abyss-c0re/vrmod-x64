Lavender's VRmod X64 Pull. <br/>
So, I did a few key things <br/>

1. cl_character now uses the same IK as base VRmod. This means characters using the proportion trick will now work correctly. <br/>
This also includes being able to change the eye height and the HMD to Head distance of player models. <br/>

2. Arm Extension has been added, which will extend the players arm beyond the physical limit of the playermodel. <br/>
This will allow the hands to always match the players hand position, at the cost of looking strange on certain playermodels. <br/>

3. Animations can be disabled. <br/>
This exists for future FBT implimentation, as games with FBT let you disable the animations (mostly). This does not make the player body move with the arms when disabled.<br/>
It's imperfect, and not very useful for most players, however this is gonna be a nice QOL feature for FBT, and does have some use for players without it. <br/>

4. Melee attacks will no longer start fires. <br/>
VRmod used to do DMG_BLAST for blunt damage. This was done so that the func_breakable_surf glass on cs_office could be broken, which Abyss-Core needed. <br/>
This fix makes it do DMG_CLUB for all surfaces except glass func_breakable_surf, which still gets DMG_BLAST. Satisfing everyone. <br/>

This also includes a 1 line change to cl_ui to fix the laser for the mirror menu not appearing. <br/>
This just changes "menuFocusDist then return end" to "menuFocusDist then continue end" <br/>

These changes were tested on Win 11, no clue on how it is on Linux.  <br/>
