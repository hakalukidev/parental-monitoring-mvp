package com.example.childapp.blocker

import java.net.IDN
import java.net.URI
import java.util.Locale

data class WebAddress(val host: String, val exact: String, val hasPath: Boolean)

/** Matches DNS boundaries; never falls back to arbitrary text as a hostname. */
object WebAddresses {
    fun parse(input: String, allowSingleLabel: Boolean = false): WebAddress? = try {
        val value = input.trim()
        require(value.isNotEmpty() && value.length <= 4096 && !value.any { it.isWhitespace() || it < ' ' || it == '\\' })
        require(!value.contains(':') || value.startsWith("http://", true) || value.startsWith("https://", true))
        val uri = URI(if (value.startsWith("http://", true) || value.startsWith("https://", true)) value else "https://$value")
        val scheme = uri.scheme.lowercase(Locale.ROOT)
        require(scheme == "http" || scheme == "https")
        val authority = uri.rawAuthority ?: error("Missing host")
        require(!authority.contains('@') && !authority.contains('*') && !authority.contains('%'))
        val rawHost = authority.substringBefore(':').trimEnd('.')
        require(rawHost.none { it in "ßς\u200c\u200d" })
        val host = IDN.toASCII(rawHost, IDN.USE_STD3_ASCII_RULES).lowercase(Locale.ROOT)
        require(host.length <= 253 && (host.split('.').size >= 2 || (allowSingleLabel && host.matches(Regex("[a-z]{2,63}")))) && host.split('.').all { it.matches(Regex("[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")) })
        val portText = authority.substringAfter(':', "")
        val port = if (portText.isEmpty()) -1 else portText.toInt().also { require(it in 1..65535) }
        val defaultPort = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
        val path = canonicalPath(uri.rawPath?.ifEmpty { "/" } ?: "/")
        val query = uri.rawQuery?.let { "?$it" } ?: ""
        val exact = URI("$scheme://${host.removePrefix("www.")}${if (port == -1 || defaultPort) "" else ":$port"}$path$query").toASCIIString()
            .replace(Regex("%[0-9a-fA-F]{2}")) { it.value.uppercase(Locale.ROOT) }
        WebAddress(host, exact, path != "/" || query.isNotEmpty() || (port != -1 && !defaultPort))
    } catch (_: Exception) { null }

    private fun canonicalPath(path: String): String {
        val parts = path.split('/')
        val result = mutableListOf<String>()
        parts.forEachIndexed { index, part ->
            val dot = part.replace(Regex("%2e", RegexOption.IGNORE_CASE), ".")
            when (dot) {
                "." -> if (index == parts.lastIndex) result.add("")
                ".." -> { if (result.size > 1) result.removeAt(result.lastIndex); if (index == parts.lastIndex) result.add("") }
                else -> result.add(part)
            }
        }
        return result.joinToString("/").ifEmpty { "/" }
    }

    fun matches(type: String, target: String, address: WebAddress?): Boolean {
        if (address == null) return false
        val wildcard = target.trim().startsWith("*.")
        val rule = parse(target.trim().removePrefix("*."), allowSingleLabel = wildcard) ?: return false
        if (type == "URL" || rule.hasPath) return !wildcard && address.exact == rule.exact
        val host = rule.host.removePrefix("www.")
        return address.host.endsWith(".$host") || address.host.removePrefix("www.") == host
    }
}
