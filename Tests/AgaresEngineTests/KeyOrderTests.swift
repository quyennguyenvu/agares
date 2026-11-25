import Testing
@testable import AgaresEngine

/// A syllable as Telex sees it: its plain letters, and the mark and tone keys with the letter each
/// one has to come after.
struct Word: Sendable, CustomTestStringConvertible {
    let letters: String
    let marks: [(after: Int, key: Character)]
    let result: String

    init(_ letters: String, _ marks: [(Int, Character)], _ result: String) {
        self.letters = letters
        self.marks = marks.map { (after: $0.0, key: $0.1) }
        self.result = result
    }

    var testDescription: String { result }

    /// Every order of typing the word in which each mark key comes somewhere after its letter.
    var keyOrders: Set<String> {
        // Each key carries the index of the plain letter it is, so positions survive the insertions.
        var orders: [[(key: Character, letter: Int?)]] = [letters.enumerated().map { (key: $1, letter: $0) }]
        for mark in marks {
            orders = orders.flatMap { order -> [[(key: Character, letter: Int?)]] in
                let earliest = order.firstIndex { $0.letter == mark.after }! + 1
                return (earliest...order.count).map { position in
                    var next = order
                    next.insert((key: mark.key, letter: nil), at: position)
                    return next
                }
            }
        }
        return Set(orders.map { String($0.map(\.key)) })
    }
}

/// One word or more for every vowel group Vietnamese has, plus the gi and qu initials.
private let words: [Word] = [
    // One vowel
    Word("ba", [(1, "f")], "bà"),
    Word("bat", [(1, "w"), (1, "s")], "bắt"),
    Word("can", [(1, "a"), (1, "f")], "cần"),
    Word("me", [(1, "j")], "mẹ"),
    Word("len", [(1, "e")], "lên"),
    Word("be", [(1, "e"), (1, "s")], "bế"),
    Word("di", [(0, "d")], "đi"),
    Word("co", [(1, "s")], "có"),
    Word("khong", [(2, "o")], "không"),
    Word("cho", [(2, "w"), (2, "f")], "chờ"),
    Word("du", [(0, "d"), (1, "r")], "đủ"),
    Word("tu", [(1, "w"), (1, "f")], "từ"),
    Word("my", [(1, "x")], "mỹ"),
    // Two vowels
    Word("mai", [(1, "s")], "mái"),
    Word("chao", [(2, "s")], "cháo"),
    Word("mau", [(1, "f")], "màu"),
    Word("nay", [(1, "f")], "này"),
    Word("dau", [(0, "d"), (1, "a"), (1, "f")], "đầu"),
    Word("day", [(0, "d"), (1, "a"), (1, "s")], "đấy"),
    Word("lay", [(1, "a"), (1, "s")], "lấy"),
    Word("thay", [(2, "a"), (2, "s")], "thấy"),
    Word("keo", [(1, "j")], "kẹo"),
    Word("neu", [(1, "e"), (1, "s")], "nếu"),
    Word("mia", [(1, "s")], "mía"),
    Word("tieng", [(2, "e"), (1, "s")], "tiếng"),
    Word("viet", [(2, "e"), (1, "j")], "việt"),
    Word("diu", [(1, "j")], "dịu"),
    Word("hoa", [(1, "f")], "hòa"),
    Word("hoan", [(1, "f")], "hoàn"),
    Word("hoac", [(2, "w"), (1, "j")], "hoặc"),
    Word("xoan", [(2, "w")], "xoăn"),
    Word("khoe", [(2, "r")], "khỏe"),
    Word("noi", [(1, "s")], "nói"),
    Word("toi", [(1, "o")], "tôi"),
    Word("roi", [(1, "o"), (1, "f")], "rồi"),
    Word("moi", [(1, "w"), (1, "s")], "mới"),
    Word("cua", [(1, "r")], "của"),
    Word("xuan", [(2, "a")], "xuân"),
    Word("luat", [(2, "a"), (1, "j")], "luật"),
    Word("thue", [(3, "e"), (2, "s")], "thuế"),
    Word("tui", [(1, "s")], "túi"),
    Word("muon", [(2, "o"), (1, "s")], "muốn"),
    Word("buon", [(2, "o"), (1, "f")], "buồn"),
    // uơ at the end of a word needs its w after the o
    Word("thuo", [(3, "w"), (2, "r")], "thuở"),
    Word("thuy", [(2, "r")], "thủy"),
    Word("huynh", [(1, "f")], "huỳnh"),
    Word("mua", [(1, "w")], "mưa"),
    Word("lua", [(1, "w"), (1, "r")], "lửa"),
    Word("gui", [(1, "w"), (1, "r")], "gửi"),
    Word("cuu", [(1, "w"), (1, "s")], "cứu"),
    Word("duoc", [(0, "d"), (1, "w"), (1, "j")], "được"),
    Word("duong", [(0, "d"), (1, "w"), (1, "f")], "đường"),
    Word("nuoc", [(1, "w"), (1, "s")], "nước"),
    Word("muon", [(1, "w"), (1, "j")], "mượn"),
    Word("yen", [(1, "e")], "yên"),
    // Three vowels
    Word("dieu", [(0, "d"), (2, "e"), (1, "f")], "điều"),
    Word("lieu", [(2, "e"), (1, "j")], "liệu"),
    Word("yeu", [(1, "e")], "yêu"),
    Word("yeu", [(1, "e"), (0, "s")], "yếu"),
    Word("ngoai", [(2, "f")], "ngoài"),
    Word("ngoao", [(2, "s")], "ngoáo"),
    Word("xoay", [(1, "s")], "xoáy"),
    Word("ngoeo", [(2, "j")], "ngoẹo"),
    Word("khuay", [(3, "a"), (2, "s")], "khuấy"),
    Word("tuoi", [(2, "o"), (1, "r")], "tuổi"),
    Word("cuoi", [(2, "o"), (1, "s")], "cuối"),
    Word("khuya", [], "khuya"),
    Word("nguyen", [(4, "e"), (2, "x")], "nguyễn"),
    Word("chuyen", [(4, "e"), (2, "r")], "chuyển"),
    Word("khuyu", [(2, "r")], "khuỷu"),
    Word("nguoi", [(2, "w"), (2, "f")], "người"),
    Word("muoi", [(1, "w"), (1, "f")], "mười"),
    Word("ruou", [(1, "w"), (1, "j")], "rượu"),
    Word("huou", [(1, "w")], "hươu"),
    // gi and qu
    Word("gi", [(1, "f")], "gì"),
    Word("gia", [(1, "f")], "già"),
    Word("giet", [(2, "e"), (1, "s")], "giết"),
    Word("giua", [(2, "w"), (1, "x")], "giữa"),
    Word("giuong", [(2, "w"), (2, "f")], "giường"),
    Word("gioi", [(2, "r")], "giỏi"),
    Word("qua", [(2, "f")], "quà"),
    Word("quy", [(2, "s")], "quý"),
    Word("quoc", [(2, "o"), (2, "s")], "quốc"),
    Word("quyet", [(3, "e"), (2, "s")], "quyết"),
    Word("qua", [(2, "r")], "quả"),
    Word("quen", [(2, "e")], "quên"),
    Word("quan", [(2, "a")], "quân"),
    Word("quang", [(2, "w")], "quăng"),
    Word("quo", [(2, "w")], "quơ"),
    Word("giay", [(2, "a"), (1, "s")], "giấy"),
    // Words that start with their vowel
    Word("an", [(0, "w")], "ăn"),
    Word("am", [(0, "a"), (0, "s")], "ấm"),
    Word("ay", [(0, "a"), (0, "s")], "ấy"),
    Word("ao", [(0, "s")], "áo"),
    Word("ong", [(0, "o")], "ông"),
    Word("oc", [(0, "o"), (0, "s")], "ốc"),
    Word("oi", [(0, "w")], "ơi"),
    Word("ua", [(0, "w")], "ưa"),
    Word("uoc", [(0, "w"), (0, "s")], "ước"),
    Word("uong", [(1, "o"), (0, "s")], "uống"),
    Word("oan", [(0, "s")], "oán"),
    // ch and nh finals, three-letter initials
    Word("cach", [(1, "s")], "cách"),
    Word("benh", [(1, "e"), (1, "j")], "bệnh"),
    Word("thich", [(2, "s")], "thích"),
    Word("hoach", [(1, "j")], "hoạch"),
    Word("tuyet", [(3, "e"), (1, "j")], "tuyệt"),
    Word("thuong", [(2, "w")], "thương"),
    Word("muong", [(2, "o"), (1, "s")], "muống"),
    Word("nghieng", [(4, "e")], "nghiêng"),
    Word("nghi", [(3, "x")], "nghĩ"),
    // A bare w typed as the letter ư
    Word("tw", [(1, "f")], "từ"),
    Word("nhw", [], "như"),
    Word("mwa", [], "mưa"),
    Word("lwa", [(1, "r")], "lửa"),
    Word("cwu", [(1, "s")], "cứu"),
    Word("hwong", [], "hương"),
    Word("nwoc", [(1, "s")], "nước"),
    Word("dwoc", [(0, "d"), (1, "j")], "được"),
    Word("ngwoi", [(2, "f")], "người"),
]

@Test(arguments: words)
func everyKeyOrderGivesTheSameWord(word: Word) {
    for keys in word.keyOrders.sorted() {
        #expect(typed(keys) == word.result, "typing \(keys)")
        #expect(typed(keys.uppercased()) == word.result.uppercased(), "typing \(keys.uppercased())")
        // The start of a sentence: only the first key is a capital.
        let capitalized = keys.prefix(1).uppercased() + keys.dropFirst()
        #expect(typed(capitalized) == word.result.prefix(1).uppercased() + word.result.dropFirst(), "typing \(capitalized)")
    }
}
