package com.meo.network

/**
 * A computer address to stream to.
 *
 * Accepts what the desktop apps put in their QR code (`meomic://192.168.1.5:48888`)
 * as well as what people type by hand (`192.168.1.5`, `192.168.1.5:48888`).
 *
 * IPv6 literals are not accepted: the rest of the app resolves and streams over
 * IPv4, so taking one here would only fail later with a worse message.
 */
data class ConnectionTarget(val host: String, val port: Int) {

    companion object {
        const val SCHEME = "meomic"

        private val HOST_CHARACTERS = { character: Char ->
            character.isLetterOrDigit() || character == '.' || character == '-' || character == '_'
        }

        /** Returns null for anything that is not an address we can dial. */
        fun parse(raw: String?): ConnectionTarget? {
            var text = raw?.trim().orEmpty()
            if (text.isEmpty()) return null

            if (text.contains("://")) {
                if (!text.substringBefore("://").equals(SCHEME, ignoreCase = true)) return null
                text = text.substringAfter("://")
            }

            // A trailing slash is common when a QR code is generated from a URL
            // builder; anything else path-like is not an address.
            text = text.trimEnd('/')
            if (text.isEmpty() || text.contains('/') || text.any { it.isWhitespace() }) return null

            val separator = text.lastIndexOf(':')
            val host: String
            val port: Int

            if (separator >= 0) {
                host = text.substring(0, separator)
                port = text.substring(separator + 1).toIntOrNull() ?: return null
                if (port !in 1..65535) return null
            } else {
                host = text
                port = UdpAudioStreamer.DEFAULT_PORT
            }

            if (host.isEmpty() || !host.all(HOST_CHARACTERS)) return null

            return ConnectionTarget(host, port)
        }
    }
}
