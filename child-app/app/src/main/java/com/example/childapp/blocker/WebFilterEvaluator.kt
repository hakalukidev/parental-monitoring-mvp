package com.example.childapp.blocker

import android.content.Context
import com.example.childapp.data.CachedWebRule
import com.example.childapp.data.LocalDatabase
import java.net.URI

data class WebCheckResult(
    val isBlocked: Boolean,
    val matchedRule: CachedWebRule? = null,
    val category: String = "GENERAL",
    val reason: String? = null
)

object WebFilterEvaluator {

    fun evaluateUrl(context: Context, rawUrl: String, title: String = ""): WebCheckResult {
        val normalizedUrl = if (!rawUrl.startsWith("http://") && !rawUrl.startsWith("https://")) {
            "https://$rawUrl"
        } else {
            rawUrl
        }

        val domain = try {
            val uri = URI(normalizedUrl)
            uri.host?.lowercase() ?: extractDomainFallback(normalizedUrl)
        } catch (_: Exception) {
            extractDomainFallback(normalizedUrl)
        }

        val lowerUrl = normalizedUrl.lowercase()
        val lowerDomain = domain.lowercase()
        val lowerTitle = title.lowercase()

        val rules = LocalDatabase.getInstance(context).getAllActiveWebRules()

        // 1. Check direct ALLOW rules first
        for (rule in rules) {
            if (rule.action == "ALLOW" && matchesRule(rule, lowerUrl, lowerDomain, lowerTitle)) {
                return WebCheckResult(isBlocked = false, matchedRule = rule)
            }
        }

        // 2. Check BLOCK rules
        for (rule in rules) {
            if (rule.action == "BLOCK" && matchesRule(rule, lowerUrl, lowerDomain, lowerTitle)) {
                val cat = resolveCategory(rule, lowerUrl, lowerDomain)
                return WebCheckResult(
                    isBlocked = true,
                    matchedRule = rule,
                    category = cat,
                    reason = "Blocked by rule: ${rule.target}"
                )
            }
        }

        // 3. Classify general category
        val category = classifyCategory(lowerUrl, lowerDomain)
        return WebCheckResult(isBlocked = false, category = category)
    }

    private fun matchesRule(
        rule: CachedWebRule,
        lowerUrl: String,
        lowerDomain: String,
        lowerTitle: String
    ): Boolean {
        val target = rule.target.lowercase().trim()
        when (rule.ruleType) {
            "DOMAIN" -> {
                val cleanTarget = target.removePrefix("*.").removePrefix("*").removeSuffix("*")
                return lowerDomain == cleanTarget || lowerDomain.endsWith(".$cleanTarget")
            }
            "KEYWORD" -> {
                val cleanKeyword = target.removePrefix("*").removeSuffix("*")
                return lowerUrl.contains(cleanKeyword) || lowerTitle.contains(cleanKeyword)
            }
            "CATEGORY" -> {
                when (target.uppercase()) {
                    "ADULT", "PORNOGRAPHY" -> return isAdultContent(lowerUrl, lowerDomain)
                    "GAMBLING", "BETTING" -> return isGamblingContent(lowerUrl, lowerDomain)
                    "GAMING" -> return isGamingContent(lowerDomain)
                    "SOCIAL" -> return isSocialContent(lowerDomain)
                    "VIOLENCE" -> return isViolenceContent(lowerUrl)
                }
            }
        }
        return false
    }

    private fun resolveCategory(rule: CachedWebRule, lowerUrl: String, lowerDomain: String): String {
        if (rule.ruleType == "CATEGORY") {
            return rule.target.uppercase()
        }
        return classifyCategory(lowerUrl, lowerDomain)
    }

    fun classifyCategory(lowerUrl: String, lowerDomain: String): String {
        if (isAdultContent(lowerUrl, lowerDomain)) return "ADULT"
        if (isGamblingContent(lowerUrl, lowerDomain)) return "SUSPICIOUS"
        if (isGamingContent(lowerDomain)) return "GAMING"
        if (isSocialContent(lowerDomain)) return "SOCIAL"
        if (lowerDomain.contains("wikipedia") || lowerDomain.contains("edu") || lowerDomain.contains("khanacademy") || lowerDomain.contains("nationalgeographic")) {
            return "EDUCATION"
        }
        if (lowerDomain.contains("youtube") || lowerDomain.contains("netflix") || lowerDomain.contains("spotify")) {
            return "ENTERTAINMENT"
        }
        return "GENERAL"
    }

    private fun isAdultContent(url: String, domain: String): Boolean {
        val adultKeywords = listOf("porn", "xxx", "adult", "sex", "hentai", "xvideos", "pornhub", "xnxx", "erotic")
        return adultKeywords.any { url.contains(it) || domain.contains(it) }
    }

    private fun isGamblingContent(url: String, domain: String): Boolean {
        val gamblingKeywords = listOf("casino", "betting", "poker", "slots", "roulette", "blackjack", "jackpot", "lottery")
        return gamblingKeywords.any { url.contains(it) || domain.contains(it) }
    }

    private fun isGamingContent(domain: String): Boolean {
        val gamingDomains = listOf("roblox.com", "steampowered.com", "epicgames.com", "discord.com", "twitch.tv", "minecraft.net")
        return gamingDomains.any { domain.contains(it) }
    }

    private fun isSocialContent(domain: String): Boolean {
        val socialDomains = listOf("tiktok.com", "instagram.com", "facebook.com", "snapchat.com", "twitter.com", "x.com", "reddit.com")
        return socialDomains.any { domain.contains(it) }
    }

    private fun isViolenceContent(url: String): Boolean {
        val violenceKeywords = listOf("gore", "beheading", "weapons", "extremist", "terrorist")
        return violenceKeywords.any { url.contains(it) }
    }

    private fun extractDomainFallback(url: String): String {
        val cleaned = url.removePrefix("https://").removePrefix("http://")
        val slashIdx = cleaned.indexOf('/')
        return if (slashIdx != -1) cleaned.substring(0, slashIdx) else cleaned
    }
}
