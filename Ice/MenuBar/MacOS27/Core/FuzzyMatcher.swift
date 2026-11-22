//
//  FuzzyMatcher.swift
//  MacBar
//

import Foundation

/// Case-insensitive fuzzy subsequence matcher with word-boundary and camelCase weighting.
enum FuzzyMatcher {
    /// Returns a relevance score when all characters of `query` appear in order in `candidate`,
    /// or `nil` when `candidate` does not match. Higher scores indicate better matches.
    static func score(query: String, candidate: String) -> Double? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 1.0
        }

        let queryChars = Array(trimmed)
        let queryLower = Array(trimmed.lowercased())
        let candChars = Array(candidate)
        let candLower = Array(candidate.lowercased())

        let qCount = queryLower.count
        let cCount = candLower.count
        guard qCount <= cCount else {
            return nil
        }

        // Fast subsequence pre-check.
        var qi = 0
        for c in candLower where c == queryLower[qi] {
            qi += 1
            if qi == qCount {
                break
            }
        }
        guard qi == qCount else {
            return nil
        }

        // Dynamic programming over character alignments for optimal boundary/consecutive matches.
        let negInf = -1e9
        var dp = [Double](repeating: negInf, count: cCount)

        for ci in 0..<cCount where candLower[ci] == queryLower[0] {
            dp[ci] = characterScore(
                queryChar: queryChars[0],
                candChars: candChars,
                index: ci,
                prevIndex: nil
            )
        }

        if qCount > 1 {
            for qIndex in 1..<qCount {
                var nextDP = [Double](repeating: negInf, count: cCount)
                var bestPrevScore = negInf
                var bestPrevIndex = -1

                for ci in 0..<cCount {
                    if ci > 0 && dp[ci - 1] > negInf {
                        // Compare carrying forward bestPrevIndex vs starting from ci - 1.
                        let candScore = dp[ci - 1]
                        if bestPrevIndex == -1 || (candScore - gapPenalty(ci - (ci - 1) - 1)) >= (bestPrevScore - gapPenalty(ci - bestPrevIndex - 1)) {
                            bestPrevScore = candScore
                            bestPrevIndex = ci - 1
                        }
                    }

                    guard candLower[ci] == queryLower[qIndex], bestPrevIndex >= 0 else {
                        continue
                    }

                    // Check all valid previous positions to avoid greedy approximation on gaps.
                    var best = negInf
                    for prev in 0..<ci where dp[prev] > negInf {
                        let step = dp[prev] + characterScore(
                            queryChar: queryChars[qIndex],
                            candChars: candChars,
                            index: ci,
                            prevIndex: prev
                        )
                        if step > best {
                            best = step
                        }
                    }
                    nextDP[ci] = best
                }

                dp = nextDP
            }
        }

        guard let bestAlignment = dp.max(), bestAlignment > negInf else {
            return nil
        }

        var total = bestAlignment
        let lowerCandidate = String(candLower)
        let lowerQuery = String(queryLower)
        if lowerCandidate == lowerQuery {
            total += 50
        } else if lowerCandidate.hasPrefix(lowerQuery) {
            total += 30
        } else if lowerCandidate.contains(lowerQuery) {
            total += 14
        }

        total -= Double(cCount) * 0.25
        return total
    }

    private static func characterScore(
        queryChar: Character,
        candChars: [Character],
        index: Int,
        prevIndex: Int?
    ) -> Double {
        var score = 10.0

        if candChars[index] == queryChar {
            score += 2.0
        }

        if index == 0 {
            score += 24.0
        } else {
            let prevChar = candChars[index - 1]
            let currChar = candChars[index]
            if isBoundarySeparator(prevChar) {
                score += 20.0
            } else if prevChar.isLowercase && currChar.isUppercase {
                score += 20.0
            }
        }

        if let prevIndex {
            let gap = index - prevIndex - 1
            if gap == 0 {
                score += 18.0
            } else {
                score -= gapPenalty(gap)
            }
        }

        return score
    }

    private static func gapPenalty(_ gap: Int) -> Double {
        Double(min(max(gap, 0), 8)) * 1.5
    }

    private static func isBoundarySeparator(_ char: Character) -> Bool {
        char == " " || char == "-" || char == "_" || char == "." || char == "/"
    }
}
