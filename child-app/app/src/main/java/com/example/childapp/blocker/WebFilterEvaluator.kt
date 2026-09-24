package com.example.childapp.blocker

import android.content.Context
import com.example.childapp.data.CachedWebRule
import com.example.childapp.data.LocalDatabase
import java.net.URI
import java.net.URLDecoder

data class WebCheckResult(
    val isBlocked: Boolean,
    val matchedRule: CachedWebRule? = null,
    val category: String = "GENERAL",
    val reason: String? = null
)

object WebFilterEvaluator {

    fun evaluateUrl(context: Context, rawUrl: String, title: String = ""): WebCheckResult {
        val trimmedRaw = rawUrl.trim()
        val decodedRaw = safeDecode(trimmedRaw)

        val normalizedUrl = if (!trimmedRaw.startsWith("http://") && !trimmedRaw.startsWith("https://")) {
            "https://$trimmedRaw"
        } else {
            trimmedRaw
        }

        val decodedUrl = safeDecode(normalizedUrl)

        val domain = try {
            val uri = URI(normalizedUrl)
            uri.host?.lowercase() ?: extractDomainFallback(normalizedUrl)
        } catch (_: Exception) {
            extractDomainFallback(normalizedUrl)
        }

        val searchQuery = extractSearchQuery(normalizedUrl).ifBlank {
            if (!rawUrl.startsWith("http://") && !rawUrl.startsWith("https://") && !rawUrl.contains(".")) {
                decodedRaw
            } else {
                ""
            }
        }

        val lowerUrl = decodedUrl.lowercase()
        val lowerRaw = decodedRaw.lowercase()
        val lowerDomain = domain.lowercase()
        val lowerTitle = safeDecode(title).lowercase()
        val lowerQuery = searchQuery.lowercase()

        val rules = LocalDatabase.getInstance(context).getAllActiveWebRules()

        // 1. Check direct ALLOW rules first
        for (rule in rules) {
            if (rule.action == "ALLOW" && matchesRule(rule, lowerUrl, lowerRaw, lowerDomain, lowerTitle, lowerQuery)) {
                return WebCheckResult(isBlocked = false, matchedRule = rule)
            }
        }

        // 2. Check BLOCK rules
        for (rule in rules) {
            if (rule.action == "BLOCK" && matchesRule(rule, lowerUrl, lowerRaw, lowerDomain, lowerTitle, lowerQuery)) {
                val cat = resolveCategory(rule, lowerUrl, lowerDomain)
                return WebCheckResult(
                    isBlocked = true,
                    matchedRule = rule,
                    category = cat,
                    reason = "Access to '${rule.target}' has been blocked by your parent."
                )
            }
        }

        // 3. Classify general category
        val category = classifyCategory(lowerUrl, lowerDomain, lowerQuery)
        return WebCheckResult(isBlocked = false, category = category)
    }

    private fun matchesRule(
        rule: CachedWebRule,
        lowerUrl: String,
        lowerRaw: String,
        lowerDomain: String,
        lowerTitle: String,
        lowerQuery: String
    ): Boolean {
        val target = rule.target.lowercase().trim()
        if (target.isBlank()) return false

        when (rule.ruleType) {
            "DOMAIN" -> {
                val cleanTarget = target.removePrefix("*.").removePrefix("*").removeSuffix("*").trim()
                if (cleanTarget.isBlank()) return false
                return lowerDomain == cleanTarget ||
                        lowerDomain.endsWith(".$cleanTarget") ||
                        lowerRaw == cleanTarget ||
                        lowerRaw.startsWith("$cleanTarget/")
            }
            "KEYWORD" -> {
                val cleanKeyword = target.removePrefix("*").removeSuffix("*").trim()
                if (cleanKeyword.isBlank()) return false
                return lowerUrl.contains(cleanKeyword) ||
                        lowerRaw.contains(cleanKeyword) ||
                        lowerTitle.contains(cleanKeyword) ||
                        lowerQuery.contains(cleanKeyword) ||
                        lowerDomain.contains(cleanKeyword)
            }
            "CATEGORY" -> {
                when (target.uppercase()) {
                    "ADULT", "PORNOGRAPHY" -> return isAdultContent(lowerUrl, lowerDomain, lowerQuery)
                    "GAMBLING", "BETTING" -> return isGamblingContent(lowerUrl, lowerDomain, lowerQuery)
                    "GAMING" -> return isGamingContent(lowerDomain, lowerQuery)
                    "SOCIAL" -> return isSocialContent(lowerDomain, lowerQuery)
                    "VIOLENCE" -> return isViolenceContent(lowerUrl, lowerQuery)
                }
            }
        }
        return false
    }

    private fun resolveCategory(rule: CachedWebRule, lowerUrl: String, lowerDomain: String): String {
        if (rule.ruleType == "CATEGORY") {
            return rule.target.uppercase()
        }
        return classifyCategory(lowerUrl, lowerDomain, "")
    }

    fun classifyCategory(lowerUrl: String, lowerDomain: String, lowerQuery: String = ""): String {
        if (isAdultContent(lowerUrl, lowerDomain, lowerQuery)) return "ADULT"
        if (isGamblingContent(lowerUrl, lowerDomain, lowerQuery)) return "SUSPICIOUS"
        if (isGamingContent(lowerDomain, lowerQuery)) return "GAMING"
        if (isSocialContent(lowerDomain, lowerQuery)) return "SOCIAL"
        if (lowerDomain.contains("wikipedia") || lowerDomain.contains("edu") || lowerDomain.contains("khanacademy") || lowerDomain.contains("nationalgeographic")) {
            return "EDUCATION"
        }
        if (lowerDomain.contains("youtube") || lowerDomain.contains("netflix") || lowerDomain.contains("spotify")) {
            return "ENTERTAINMENT"
        }
        return "GENERAL"
    }

    private fun isAdultContent(url: String, domain: String, query: String): Boolean {
        val adultKeywords = listOf("porn", "xxx", "adult", "sex", "hentai", "xvideos", "pornhub", "xnxx", "erotic")
        return adultKeywords.any { url.contains(it) || domain.contains(it) || query.contains(it) }
    }

    private fun isGamblingContent(url: String, domain: String, query: String): Boolean {
        val gamblingKeywords = listOf("casino", "betting", "poker", "slots", "roulette", "blackjack", "jackpot", "lottery", "1xbet", "bet365")
        return gamblingKeywords.any { url.contains(it) || domain.contains(it) || query.contains(it) }
    }

    private fun isGamingContent(domain: String, query: String): Boolean {
        val gamingDomains = listOf("roblox.com", "steampowered.com", "epicgames.com", "discord.com", "twitch.tv", "minecraft.net")
        return gamingDomains.any { domain.contains(it) || query.contains(it) }
    }

    private fun isSocialContent(domain: String, query: String): Boolean {
        val socialDomains = listOf("tiktok.com", "instagram.com", "facebook.com", "snapchat.com", "twitter.com", "x.com", "reddit.com")
        return socialDomains.any { domain.contains(it) }
    }

    private fun isViolenceContent(url: String, query: String): Boolean {
        val violenceKeywords = listOf("gore", "beheading", "weapons", "extremist", "terrorist")
        return violenceKeywords.any { url.contains(it) || query.contains(it) }
    }

    private fun extractDomainFallback(url: String): String {
        val cleaned = url.removePrefix("https://").removePrefix("http://")
        val slashIdx = cleaned.indexOf('/')
        return if (slashIdx != -1) cleaned.substring(0, slashIdx) else cleaned
    }

    private fun extractSearchQuery(url: String): String {
        val decoded = safeDecode(url)
        val query = try {
            val uri = URI(if (decoded.startsWith("http://") || decoded.startsWith("https://")) decoded else "https://$decoded")
            uri.rawQuery ?: if (decoded.contains("?")) decoded.substringAfter("?") else ""
        } catch (_: Exception) {
            if (decoded.contains("?")) decoded.substringAfter("?") else ""
        }

        if (query.isNotBlank()) {
            val params = query.split("&")
            for (param in params) {
                val parts = param.split("=", limit = 2)
                if (parts.size == 2) {
                    val key = safeDecode(parts[0]).lowercase().trim()
                    val value = safeDecode(parts[1]).replace("+", " ").trim()
                    if (key in listOf("q", "query", "search_query", "p", "k", "text", "keyword", "wd", "search")) {
                        return value
                    }
                }
            }
        }
        return ""
    }

    private fun safeDecode(str: String): String {
        return try {
            URLDecoder.decode(str, "UTF-8")
        } catch (_: Exception) {
            str
        }
    }
}
