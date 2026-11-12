package com.pulseagent.app

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class AgentCallScreeningService : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        val handle = callDetails.handle
        val phoneNumber = handle?.schemeSpecificPart ?: "Неизвестный номер"

        if (!MainActivity.spamScreeningEnabled) {
            respondToCall(callDetails, CallResponse.Builder().build())
            return
        }

        val bridge = SystemActionBridge(applicationContext)
        val isKnown = bridge.isKnownNumber(phoneNumber)

        if (isKnown) {
            respondToCall(callDetails, CallResponse.Builder().build())
        } else {
            // Заглушаем звонок для владельца и передаём карточку в ИИ-секретарь
            val response = CallResponse.Builder()
                .setSilenceCall(true)
                .build()
            respondToCall(callDetails, response)

            MainActivity.notifyCallScreened(
                mapOf(
                    "number" to phoneNumber,
                    "transcript" to "Входящий с незнакомого номера. Звонок переведён на голосового секретаря: «Кто это и по какому вопросу?»",
                    "action" to "Звонок перехвачен Антиспам-секретарём"
                )
            )
        }
    }
}
