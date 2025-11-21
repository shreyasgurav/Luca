const { callOpenAI } = require('../lib/openaiClient');

function extractAssistantText(openAIResponse) {
  try {
    // Extract from o3 Responses API format
    if (openAIResponse.output && Array.isArray(openAIResponse.output)) {
      const messageOutput = openAIResponse.output.find(item => item.type === 'message');
      if (messageOutput && messageOutput.content && Array.isArray(messageOutput.content)) {
        const textContent = messageOutput.content.find(item => item.type === 'output_text');
        if (textContent && textContent.text) {
          return textContent.text;
        }
      }
    }
    // Fallback
    return openAIResponse.output_text || openAIResponse.choices?.[0]?.message?.content || 'No response received';
  } catch {
    return 'Failed to parse response';
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { 
    res.statusCode = 405; 
    return res.end('Method Not Allowed'); 
  }

  try {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const { content, userId, sessionId } = body || {};
    
    if (!content) { 
      res.statusCode = 400; 
      return res.end('Missing content'); 
    }

    // Create transcript-specific memory extraction prompt
    const extractionPrompt = `
You are an advanced memory extraction system specifically designed for audio transcripts. Extract important, memorable facts from audio transcripts that would be valuable for future personalized interactions.

TRANSCRIPT-SPECIFIC GUIDELINES:
- Focus on information that reveals user preferences, goals, personal details, and instructions
- Skip temporary information like current time, weather, or session-specific data
- Skip casual greetings, thanks, confirmations, or trivial responses
- Skip audio transcription artifacts, filler words, or incomplete sentences
- Only extract substantial, meaningful information that adds personal context
- Remember: transcripts may contain multiple speakers, focus on user-relevant content
- Categorize memories by type for better organization

MEMORY TYPES:
- "personal": Name, location, family, personal details mentioned by the user
- "preference": User's likes, dislikes, style preferences, communication preferences  
- "professional": Job, skills, work projects, career goals mentioned by the user
- "goal": User's objectives, targets, deadlines, aspirations
- "instruction": How user wants to be helped, specific requests made by the user
- "knowledge": Facts user shared, their expertise, interests
- "relationship": People in their life, connections mentioned
- "event": Important dates, scheduled events, milestones mentioned by the user

CONTENT TO ANALYZE:
${content}

EXAMPLES OF GOOD EXTRACTIONS FROM TRANSCRIPTS:
Input: "I'm Sarah from New York and I love working on machine learning projects"
Output: [{"kind":"personal","text":"User's name is Sarah and they're from New York","summary":"Sarah from NYC","importance":0.9,"tags":["name","location","Sarah","New York"]},{"kind":"professional","text":"User loves working on machine learning projects","summary":"ML enthusiast","importance":0.8,"tags":["machine learning","projects","interest"]}]

Input: "I prefer dark mode interfaces and I'm studying computer science"
Output: [{"kind":"preference","text":"User prefers dark mode interfaces","summary":"Dark mode preference","importance":0.7,"tags":["dark","mode","ui","preference"]},{"kind":"professional","text":"User is studying computer science","summary":"CS student","importance":0.8,"tags":["computer science","student","education"]}]

EXAMPLES OF WHAT NOT TO EXTRACT:
Input: "Hi", "Thanks", "Ok", "Good morning", "How are you?"
Output: [] (empty array - these are trivial)

Input: "Um", "Uh", "Let me think", "You know"
Output: [] (empty array - these are filler words)

Input: "The weather is nice today" or "I just had lunch"
Output: [] (empty array - these are temporary, non-memorable facts)

REQUIRED OUTPUT FORMAT - Return ONLY valid JSON array:
[
  {
    "kind": "personal|preference|professional|goal|instruction|knowledge|relationship|event",
    "text": "exact important information extracted",
    "summary": "brief summary for quick reference",
    "importance": 0.7,
    "tags": ["relevant", "keywords"]
  }
]

Rules:
- Return ONLY the JSON array, no explanations
- Importance: 0.9+ for very personal/critical info, 0.7+ for useful preferences, 0.5+ for general facts
- Each memory should be specific and actionable
- If no important information found, return empty array []
- Focus on user-relevant content, not general conversation topics

JSON OUTPUT:`;

        console.log('🧠 Extracting memories from transcript:', content.substring(0, 100) + '...');

    let result;
    try {
      result = await callOpenAI({
        imageUrl: null,
        promptContext: extractionPrompt,
        includeOCR: false,
        sessionId: sessionId || 'transcript-memory-extraction'
      });
    } catch (openAIError) {
      console.warn('⚠️ OpenAI API failed, using fallback extraction for transcript');
      return res.end(JSON.stringify({
        success: true,
        extractedFacts: fallbackTranscriptExtraction(content),
        raw: 'Used fallback extraction due to API unavailability'
      }));
    }
    
    const extractedText = extractAssistantText(result);
    
    // Try to parse the JSON response with enhanced error handling
    let extractedFacts = [];
    try {
      // Clean the response more thoroughly
      let cleanedText = extractedText;
      
      // Remove common markdown patterns
      cleanedText = cleanedText.replace(/```json\n?|\n?```|```\n?/g, '');
      
      // Remove any text before the first [ or after the last ]
      const firstBracket = cleanedText.indexOf('[');
      const lastBracket = cleanedText.lastIndexOf(']');
      
      if (firstBracket !== -1 && lastBracket !== -1 && lastBracket > firstBracket) {
        cleanedText = cleanedText.substring(firstBracket, lastBracket + 1);
      }
      
      cleanedText = cleanedText.trim();
      
      console.log('🔍 Cleaned text for parsing:', cleanedText.substring(0, 200) + '...');
      
      if (!cleanedText || cleanedText === '[]') {
        console.log('📝 No memories to extract from this transcript');
        extractedFacts = [];
      } else {
        extractedFacts = JSON.parse(cleanedText);
        
        // Validate the structure
        if (!Array.isArray(extractedFacts)) {
          throw new Error('Response is not an array');
        }
        
        // Filter and validate each fact
        extractedFacts = extractedFacts.filter(fact => {
          return fact && 
                 typeof fact.text === 'string' && 
                 typeof fact.summary === 'string' && 
                 typeof fact.importance === 'number' &&
                 fact.text.trim().length >= 6 && // allow concise facts
                 fact.importance >= 0.2; // slightly relaxed threshold
        });
        
        console.log(`✅ Extracted ${extractedFacts.length} valid memories from transcript`);
      }
      
    } catch (parseError) {
      console.warn('⚠️ Failed to parse transcript memory extraction JSON:', parseError.message);
      console.warn('Raw response (first 500 chars):', extractedText.substring(0, 500));
      console.warn('Cleaned text attempted:', cleanedText ? cleanedText.substring(0, 200) : 'null');
      
      // Fallback: try to extract basic information heuristically
      extractedFacts = fallbackTranscriptExtraction(content);
      console.log(`🔄 Fallback transcript extraction yielded ${extractedFacts.length} memories`);
    }

    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ 
      success: true,
      extractedFacts,
      raw: extractedText 
    }));
    
  } catch (err) {
    console.error('❌ Transcript memory extraction error:', err);
    res.statusCode = 500; 
    res.end(JSON.stringify({ error: err.message }));
  }
};

// Fallback extraction using simple heuristics for transcripts
function fallbackTranscriptExtraction(content) {
  // Skip trivial content in fallback too
  const trimmed = content.trim();
  if (trimmed.length < 15) return [];
  
  const trivialPatterns = ['hi', 'hello', 'hey', 'thanks', 'ok', 'okay', 'yes', 'no', 'sure', 'good', 'great', 'bye', 'um', 'uh', 'you know'];
  const lowerContent = trimmed.toLowerCase();
  if (trivialPatterns.includes(lowerContent) || trivialPatterns.includes(lowerContent.replace('.', ''))) {
    return [];
  }
  
  const facts = [];
  const sentences = content.split(/[.!?]+/).map(s => s.trim()).filter(s => s.length >= 10);
  
  for (const sentence of sentences) {
    const lowerSentence = sentence.toLowerCase();
    
    // Skip filler words and incomplete sentences
    if (lowerSentence.includes('um') || lowerSentence.includes('uh') || 
        lowerSentence.includes('you know') || lowerSentence.includes('like') ||
        lowerSentence.length < 15) {
      continue;
    }
    
    // Look for personal information patterns
    if (lowerSentence.includes('my name is') || lowerSentence.includes("i'm ") || lowerSentence.includes('i am ')) {
      facts.push({
        kind: 'personal',
        text: sentence,
        summary: `User shared: ${sentence.substring(0, 60)}...`,
        importance: 0.8,
        tags: ['personal', 'introduction']
      });
    }
    
    // Look for preferences (including short patterns)
    else if (lowerSentence.includes('i like') || lowerSentence.includes('i prefer') || 
             lowerSentence.includes('i love') || lowerSentence.includes('i hate') ||
             lowerSentence.includes('i enjoy') || lowerSentence.includes('i dislike')) {
      facts.push({
        kind: 'preference',
        text: sentence,
        summary: `User preference: ${sentence.substring(0, 60)}...`,
        importance: 0.7,
        tags: ['preference', 'likes']
      });
    }
    
    // Look for goals or projects
    else if (lowerSentence.includes('project') || lowerSentence.includes('goal') || 
             lowerSentence.includes('working on') || lowerSentence.includes('trying to') ||
             lowerSentence.includes('planning to') || lowerSentence.includes('want to')) {
      facts.push({
        kind: 'goal',
        text: sentence,
        summary: `User project/goal: ${sentence.substring(0, 60)}...`,
        importance: 0.6,
        tags: ['project', 'goal']
      });
    }
    
    // Look for professional information
    else if (lowerSentence.includes('i work') || lowerSentence.includes('i study') || 
             lowerSentence.includes('my job') || lowerSentence.includes('career')) {
      facts.push({
        kind: 'professional',
        text: sentence,
        summary: `Professional info: ${sentence.substring(0, 60)}...`,
        importance: 0.7,
        tags: ['professional', 'work']
      });
    }
  }
  
  return facts.slice(0, 3); // Limit to 3 fallback extractions
}
