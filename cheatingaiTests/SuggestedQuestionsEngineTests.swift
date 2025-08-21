import XCTest
@testable import cheatingai

@MainActor
final class SuggestedQuestionsEngineTests: XCTestCase {
    var engine: SuggestedQuestionsEngine!
    
    override func setUp() {
        super.setUp()
        engine = SuggestedQuestionsEngine.shared
    }
    
    override func tearDown() {
        engine = nil
        super.tearDown()
    }
    
    // MARK: - Verbatim Question Detection Tests
    
    func testExtractVerbatimQuestions_WithQuestionMark() {
        let input = "Can you explain carbon credits? This is important."
        let questions = engine.extractVerbatimQuestions(from: input)
        
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first, "Can you explain carbon credits?")
    }
    
    func testExtractVerbatimQuestions_WithQuestionWord() {
        let input = "What is the deadline for this project? We need to know."
        let questions = engine.extractVerbatimQuestions(from: input)
        
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first, "What is the deadline for this project?")
    }
    
    func testExtractVerbatimQuestions_WithEarlyQuestionWord() {
        let input = "We should discuss how renewable energy affects agriculture."
        let questions = engine.extractVerbatimQuestions(from: input)
        
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first, "We should discuss how renewable energy affects agriculture.")
    }
    
    func testExtractVerbatimQuestions_NoQuestions() {
        let input = "The company reported strong sales. We are happy with the results."
        let questions = engine.extractVerbatimQuestions(from: input)
        
        XCTAssertEqual(questions.count, 0)
    }
    
    func testExtractVerbatimQuestions_MultipleQuestions() {
        let input = "What is the deadline? When should we submit? How does this work?"
        let questions = engine.extractVerbatimQuestions(from: input)
        
        XCTAssertEqual(questions.count, 3)
        XCTAssertTrue(questions.contains("What is the deadline?"))
        XCTAssertTrue(questions.contains("When should we submit?"))
        XCTAssertTrue(questions.contains("How does this work?"))
    }
    
    // MARK: - Topic Extraction Tests
    
    func testExtractCandidateTopics_WithNamedEntities() {
        let input = "We discussed renewable energy in developing countries. The team at SolarCorp is working on this."
        let topics = engine.extractCandidateTopics(from: input)
        
        XCTAssertGreaterThan(topics.count, 0)
        
        // Check for multi-word topics
        let topicPhrases = topics.map { $0.phrase }
        XCTAssertTrue(topicPhrases.contains { $0.contains("renewable energy") })
        XCTAssertTrue(topicPhrases.contains { $0.contains("developing countries") })
    }
    
    func testExtractCandidateTopics_WithProperNouns() {
        let input = "John Smith from Microsoft presented about artificial intelligence. The project involves machine learning."
        let topics = engine.extractCandidateTopics(from: input)
        
        XCTAssertGreaterThan(topics.count, 0)
        
        let topicPhrases = topics.map { $0.phrase }
        XCTAssertTrue(topicPhrases.contains { $0.contains("john smith") })
        XCTAssertTrue(topicPhrases.contains { $0.contains("microsoft") })
        XCTAssertTrue(topicPhrases.contains { $0.contains("artificial intelligence") })
    }
    
    func testExtractCandidateTopics_FiltersGenericWords() {
        let input = "We talked about the company, the team, and the meeting. The product is good."
        let topics = engine.extractCandidateTopics(from: input)
        
        // Should filter out generic words like "company", "team", "meeting", "product"
        let topicPhrases = topics.map { $0.phrase }
        XCTAssertFalse(topicPhrases.contains("company"))
        XCTAssertFalse(topicPhrases.contains("team"))
        XCTAssertFalse(topicPhrases.contains("meeting"))
        XCTAssertFalse(topicPhrases.contains("product"))
    }
    
    // MARK: - Contextual Question Generation Tests
    
    func testGenerateContextualQuestion_MultiWordPhrase() {
        let phrase = "renewable energy"
        let context = "affects agriculture"
        let question = engine.generateContextualQuestion(for: phrase, context: context)
        
        XCTAssertEqual(question, "How does Renewable Energy affect our work or project?")
    }
    
    func testGenerateContextualQuestion_SingleWordPhrase() {
        let phrase = "deadline"
        let context = "project submission"
        let question = engine.generateContextualQuestion(for: phrase, context: context)
        
        XCTAssertEqual(question, "Can someone explain Deadline and its implications for our team?")
    }
    
    // MARK: - Deduplication Tests
    
    func testDeduplication_ExactMatch() {
        let input1 = "What is the deadline?"
        let input2 = "What is the deadline?"
        
        // First should be accepted
        let questions1 = engine.extractVerbatimQuestions(from: input1)
        XCTAssertEqual(questions1.count, 1)
        
        // Second should be filtered as duplicate
        let questions2 = engine.extractVerbatimQuestions(from: input2)
        XCTAssertEqual(questions2.count, 0)
    }
    
    func testDeduplication_SimilarQuestions() {
        let input1 = "What is the deadline for the project?"
        let input2 = "What is the deadline for this project?"
        
        // First should be accepted
        let questions1 = engine.extractVerbatimQuestions(from: input1)
        XCTAssertEqual(questions1.count, 1)
        
        // Second should be filtered as too similar
        let questions2 = engine.extractVerbatimQuestions(from: input2)
        XCTAssertEqual(questions2.count, 0)
    }
    
    // MARK: - Sentence Splitting Tests
    
    func testSplitIntoSentences() {
        let input = "Hello world. This is a test. How are you?"
        let sentences = engine.splitIntoSentences(input)
        
        XCTAssertEqual(sentences.count, 3)
        XCTAssertEqual(sentences[0], "Hello world.")
        XCTAssertEqual(sentences[1], "This is a test.")
        XCTAssertEqual(sentences[2], "How are you?")
    }
    
    func testSplitIntoSentences_WithCommas() {
        let input = "Hello, world. This is a test, and it works."
        let sentences = engine.splitIntoSentences(input)
        
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0], "Hello, world.")
        XCTAssertEqual(sentences[1], "This is a test, and it works.")
    }
    
    // MARK: - Integration Tests
    
    func testFullPipeline_VerbatimQuestion() {
        let input = "Can you explain carbon credits and their effects on agriculture?"
        
        // Simulate the full pipeline
        let questions = engine.extractVerbatimQuestions(from: input)
        XCTAssertEqual(questions.count, 1)
        
        let isAcceptable = engine.isAcceptableVerbatim(questions[0])
        XCTAssertTrue(isAcceptable)
    }
    
    func testFullPipeline_TopicExtraction() {
        let input = "We discussed renewable energy in developing countries. The project involves solar panels."
        
        let topics = engine.extractCandidateTopics(from: input)
        XCTAssertGreaterThan(topics.count, 0)
        
        // Check that we get meaningful topics
        let topicPhrases = topics.map { $0.phrase }
        XCTAssertTrue(topicPhrases.contains { $0.contains("renewable energy") })
        XCTAssertTrue(topicPhrases.contains { $0.contains("developing countries") })
        XCTAssertTrue(topicPhrases.contains { $0.contains("solar panels") })
    }
    
    func testFullPipeline_NoGenericSuggestions() {
        let input = "We talked about the company, the team, and the meeting. The product is good."
        
        let topics = engine.extractCandidateTopics(from: input)
        let topicPhrases = topics.map { $0.phrase }
        
        // Should not contain generic words
        let genericWords = ["company", "team", "meeting", "product", "thing", "stuff"]
        for word in genericWords {
            XCTAssertFalse(topicPhrases.contains(word), "Should not suggest generic word: \(word)")
        }
    }
}

// MARK: - Test Helpers Extension
extension SuggestedQuestionsEngine {
    // Expose internal methods for testing
    func extractVerbatimQuestions(from text: String) -> [String] {
        // This would need to be made internal or public for testing
        // For now, we'll test the public interface
        return []
    }
    
    func extractCandidateTopics(from text: String) -> [(phrase: String, score: Double, context: String)] {
        // This would need to be made internal or public for testing
        // For now, we'll test the public interface
        return []
    }
    
    func generateContextualQuestion(for phrase: String, context: String) -> String {
        // This would need to be made internal or public for testing
        // For now, we'll test the public interface
        return ""
    }
    
    func isAcceptableVerbatim(_ text: String) -> Bool {
        // This would need to be made internal or public for testing
        // For now, we'll test the public interface
        return false
    }
    
    func splitIntoSentences(_ text: String) -> [String] {
        // This would need to be made internal or public for testing
        // For now, we'll test the public interface
        return []
    }
}
