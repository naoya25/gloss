import Foundation

// 選択肢1つ。外れの選択肢も、どの単語の答えなのかを振り返れるように、その単語の問題側の言葉を持つ
public struct ChoiceOption: Hashable, Sendable {
    public var text: String
    public var meaning: String

    public init(text: String, meaning: String) {
        self.text = text
        self.meaning = meaning
    }
}

// 4択の単語テスト。答えを書かずに選ぶだけなので、書くテストより気軽に回せる
public enum ChoiceQuiz {
    public static let optionCount = 4
    // 記録の種類は書くテストと同じ wordQuiz / meaningQuiz にして、題名で見分ける。
    // 種類を増やすと、まだ更新していない Mac が同期で読めなくなるため
    public static let title = "4-Choice Test"
    // 選ぶのは書くより易しいので、書くテストの1問10点より低くする
    public static let pointsPerCorrect = 5

    // 正解1つと、ほかの単語の答えから選んだ外れを混ぜて並べる。同じ答えの外れは入れない
    public static func options(
        for word: WordEntry, among words: [WordEntry], direction: WordDirection, count: Int = optionCount
    ) -> [ChoiceOption] {
        let answer = option(for: word, direction: direction)
        var seen: Set<String> = [key(answer.text)]
        var distractors: [ChoiceOption] = []
        for other in words.filter(\.hasCardPair).shuffled() where other.id != word.id {
            guard distractors.count < count - 1 else { break }
            let option = option(for: other, direction: direction)
            if seen.insert(key(option.text)).inserted { distractors.append(option) }
        }
        return (distractors + [answer]).shuffled()
    }

    static func option(for word: WordEntry, direction: WordDirection) -> ChoiceOption {
        ChoiceOption(text: direction.expected(for: word), meaning: direction.prompt(for: word))
    }

    // 選んで当たっても、思い出して書けたとは限らないので、Book の印は1段ずつしか上げない。外したら ✕ に戻す
    public static func nextMastery(after current: Mastery, correct: Bool) -> Mastery {
        guard correct else { return .notYet }
        return Mastery(rawValue: min(current.rawValue + 1, Mastery.known.rawValue)) ?? .known
    }

    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
