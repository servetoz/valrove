package dev.valroveapp.valrove

import android.content.Context
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Short haptic effects played on the vibrator (`lib/ui/haptics.dart`).
 *
 * Flutter's haptics use View.performHapticFeedback, which plays "touch"
 * vibrations: silent when the phone's touch feedback switch is off (Samsung:
 * "Touch interactions") or in power saving mode, and some constants it uses
 * are silent on many phones anyway. These effects are "hardware feedback"
 * vibrations instead: they follow the phone's vibration strength and its
 * vibration master switch, and Valrove's own "Haptic feedback" setting
 * decides whether they are played at all.
 */
object Haptics {
    private const val CHANNEL = "dev.valroveapp.valrove/haptics"

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "play") {
                try {
                    play(app, call.arguments as? String ?: "light")
                    result.success(null)
                } catch (e: Exception) {
                    result.error("unavailable", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    fun play(context: Context, kind: String) {
        val vibrator = vibrator(context) ?: return
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            vibrator.vibrate(oneShotMillis(kind))
            return
        }
        val effect = effect(vibrator, kind)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(
                effect,
                VibrationAttributes.createForUsage(VibrationAttributes.USAGE_HARDWARE_FEEDBACK),
            )
        } else {
            vibrator.vibrate(effect)
        }
    }

    private fun effect(vibrator: Vibrator, kind: String): VibrationEffect {
        // Crisp primitives where the motor supports them (most recent phones).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            vibrator.areAllPrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_CLICK,
                VibrationEffect.Composition.PRIMITIVE_TICK,
            )
        ) {
            val composition = VibrationEffect.startComposition()
            when (kind) {
                "selection" -> composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, 0.8f)
                "light" -> composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.6f)
                "medium" -> composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.85f)
                "heavy" -> composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f)
                "error" ->
                    composition
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f, 90)
                else -> composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.6f)
            }
            return composition.compose()
        }
        // The phone's predefined effects (they fall back to a short pulse).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return VibrationEffect.createPredefined(
                when (kind) {
                    "selection" -> VibrationEffect.EFFECT_TICK
                    "heavy" -> VibrationEffect.EFFECT_HEAVY_CLICK
                    "error" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                    else -> VibrationEffect.EFFECT_CLICK
                },
            )
        }
        if (kind == "error") {
            return VibrationEffect.createWaveform(longArrayOf(0, 25, 90, 25), intArrayOf(0, 255, 0, 255), -1)
        }
        return VibrationEffect.createOneShot(oneShotMillis(kind), oneShotAmplitude(kind))
    }

    private fun oneShotMillis(kind: String): Long =
        when (kind) {
            "selection" -> 10
            "medium" -> 20
            "heavy", "error" -> 30
            else -> 14
        }

    private fun oneShotAmplitude(kind: String): Int =
        when (kind) {
            "selection" -> 90
            "medium" -> 190
            "heavy" -> 255
            else -> 140
        }
}
