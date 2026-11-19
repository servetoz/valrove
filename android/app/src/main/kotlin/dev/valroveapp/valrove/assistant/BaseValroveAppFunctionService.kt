package dev.valroveapp.valrove.assistant

import androidx.annotation.RequiresApi
import androidx.appfunctions.AppFunctionAppUnknownException
import androidx.appfunctions.AppFunctionDeclaration
import androidx.appfunctions.AppFunctionElementNotFoundException
import androidx.appfunctions.AppFunctionException
import androidx.appfunctions.AppFunctionInvalidArgumentException
import androidx.appfunctions.AppFunctionService
import androidx.appfunctions.AppFunctionServiceEntryPoint
import kotlinx.coroutines.CancellationException

/**
 * Lets assistants such as Gemini control the robot vacuum selected in Valrove
 * (Android 16+). Every function runs the same code as the app (see
 * [AssistantBridge]) and acts on the robot over the local network.
 */
@RequiresApi(36)
@AppFunctionServiceEntryPoint(
    serviceName = "ValroveAppFunctionService",
    appFunctionXmlFileName = "valrove_app_functions",
)
abstract class BaseValroveAppFunctionService : AppFunctionService() {
    /**
     * Gets what the robot vacuum is doing right now and its battery level.
     *
     * @return The robot's name, status, battery level and any problem it reports.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun getRobotStatus(): RobotStatus {
        val map = call("status") as Map<*, *>
        return RobotStatus(
            robotName = map["robotName"] as String,
            status = map["status"] as String,
            batteryPercent = (map["batteryPercent"] as Number?)?.toInt(),
            problem = map["problem"] as String?,
        )
    }

    /**
     * Lists the rooms on the robot vacuum's map. Call this to learn the room
     * names before "cleanRooms" when the user's words might not match them.
     *
     * @return The rooms, with the names the user gave them in Valrove.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun listRooms(): List<Room> =
        (call("rooms") as List<*>).map {
            val room = it as Map<*, *>
            Room(id = room["id"] as String, name = room["name"] as String)
        }

    /**
     * Lists the cleaning presets the user saved in Valrove (for example
     * "After dinner"), each a set of rooms with settings.
     *
     * @return The presets in the user's order.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun listPresets(): List<CleaningPreset> =
        (call("presets") as List<*>).map {
            val preset = it as Map<*, *>
            CleaningPreset(name = preset["name"] as String, summary = preset["summary"] as String)
        }

    /**
     * Starts cleaning the given rooms, in the given order. Room names are
     * matched leniently: "kitchen" also finds a room named "Küche".
     *
     * @param roomNames The rooms to clean, as the user named them (e.g. "kitchen", "living room").
     * @param passes How many times each room is cleaned, from 1 to the robot's maximum. Omit for once.
     * @return What the robot does now, as a sentence for the user.
     * @throws AppFunctionInvalidArgumentException If a room is not on the map (the message lists the rooms) or the robot is busy with another job. Ask the user which room they meant, or whether to stop the current job.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun cleanRooms(roomNames: List<String>, passes: Int? = null): CommandResult =
        command("cleanRooms", mapOf("rooms" to roomNames, "passes" to passes))

    /**
     * Starts cleaning the whole home with the robot's current settings.
     *
     * @return What the robot does now, as a sentence for the user.
     * @throws AppFunctionInvalidArgumentException If the robot is busy with another job. Ask the user whether to stop it first.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun cleanWholeHome(): CommandResult = command("cleanHome")

    /**
     * Starts one of the user's saved cleaning presets by name. A preset can
     * set the cleaning mode, suction and water per room and run in steps.
     *
     * @param presetName The preset's name as the user said it (e.g. "after dinner").
     * @return What the robot does now, as a sentence for the user.
     * @throws AppFunctionElementNotFoundException If there is no preset with that name (the message lists them). Ask the user which preset they meant.
     * @throws AppFunctionInvalidArgumentException If the robot is busy with another job. Ask the user whether to stop it first.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun startPreset(presetName: String): CommandResult =
        command("startPreset", mapOf("name" to presetName))

    /**
     * Pauses the robot's current cleaning; it can be resumed later.
     *
     * @return What the robot does now, as a sentence for the user.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun pauseCleaning(): CommandResult = command("pause")

    /**
     * Resumes a paused cleaning.
     *
     * @return What the robot does now, as a sentence for the user.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun resumeCleaning(): CommandResult = command("resume")

    /**
     * Stops the robot's current job where it is.
     *
     * @return What the robot does now, as a sentence for the user.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun stopCleaning(): CommandResult = command("stop")

    /**
     * Sends the robot back to its dock to charge.
     *
     * @return What the robot does now, as a sentence for the user.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot on the local network.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun returnToDock(): CommandResult = command("dock")

    /**
     * Makes the robot play a sound so the user can find it.
     *
     * @return What the robot does now, as a sentence for the user.
     * @throws AppFunctionAppUnknownException If Valrove cannot reach the robot or the robot cannot play sounds.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun locateRobot(): CommandResult = command("locate")

    private suspend fun command(method: String, arguments: Map<String, Any?> = emptyMap()) =
        CommandResult(message = call(method, arguments) as String)

    /** Runs [method] in Dart and turns its errors into AppFunction errors. */
    private suspend fun call(method: String, arguments: Map<String, Any?> = emptyMap()): Any? =
        try {
            AssistantBridge.call(applicationContext, method, arguments)
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppFunctionException) {
            throw e
        } catch (e: AssistantBridge.DartError) {
            throw when (e.code) {
                "invalid_argument" -> AppFunctionInvalidArgumentException(e.message)
                "not_found" -> AppFunctionElementNotFoundException(e.message)
                else -> AppFunctionAppUnknownException(e.message)
            }
        } catch (e: Exception) {
            throw AppFunctionAppUnknownException(e.message ?: "Valrove could not reach the robot")
        }
}
