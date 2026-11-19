package dev.valroveapp.valrove.assistant

import androidx.appfunctions.AppFunctionSerializable

/** The robot vacuum's state. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class RobotStatus(
    /** The robot's name in Valrove (e.g. "L40 Ultra"). */
    val robotName: String,
    /** What the robot is doing, e.g. "Docked", "Cleaning rooms", "Paused", "Returning" or "Error". */
    val status: String,
    /** Battery level from 0 to 100, if the robot reports it. */
    val batteryPercent: Int?,
    /** What the robot reports as wrong (e.g. "Wheel stuck"), or null when all is well. */
    val problem: String?,
)

/** A room on the robot's map. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class Room(
    /** The robot's identifier of the room. */
    val id: String,
    /** The room's name, e.g. "Kitchen", or "Room 4" for rooms without a name. */
    val name: String,
)

/** A cleaning preset saved in Valrove. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class CleaningPreset(
    /** The preset's name, e.g. "After dinner". */
    val name: String,
    /** What the preset cleans and how, e.g. "Kitchen, Dining room · 2 passes · Max". */
    val summary: String,
)

/** The outcome of a command. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class CommandResult(
    /** What happens now, as a sentence to tell the user (e.g. "Cleaning the Kitchen."). */
    val message: String,
)
