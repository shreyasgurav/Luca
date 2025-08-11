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

    // Create memory extraction prompt
    const extractionPrompt = `
You are an advanced memory extraction system inspired by ChatGPT's memory feature. Extract important, memorable facts from conversations that would be valuable for future personalized interactions.

EXTRACTION GUIDELINES:
- Focus on information that makes conversations more personal and helpful
- Extract user preferences, goals, personal details, and instructions
- Skip temporary information like current time, weather, or session-specific data
- Categorize memories by type for better organization

MEMORY TYPES:
- "personal": Name, location, family, personal details
- "preference": Likes, dislikes, style preferences, communication preferences  
- "professional": Job, skills, work projects, career goals
- "goal": Objectives, targets, deadlines, aspirations
- "instruction": How user wants to be helped, specific requests
- "knowledge": Facts user shared, expertise, interests
- "relationship": People in their life, connections
- "event": Important dates, scheduled events, milestones

CONTENT TO ANALYZE:
${content}

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

JSON OUTPUT:`;

        console.log('🧠 Extracting memories from content:', content.substring(0, 100) + '...');

    let result;
    try {
      result = await callOpenAI({
        imageUrl: null,
        promptContext: extractionPrompt,
        includeOCR: false,
        sessionId: sessionId || 'memory-extraction'
      });
    } catch (openAIError) {
      console.warn('⚠️ OpenAI API failed, using fallback extraction');
      return res.end(JSON.stringify({
        success: true,
        extractedFacts: fallbackExtraction(content),
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
        console.log('📝 No memories to extract from this content');
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
                 fact.text.length > 10 && // Skip very short extractions
                 fact.importance >= 0.3; // Skip low-importance memories
        });
        
        console.log(`✅ Extracted ${extractedFacts.length} valid memories`);
      }
      
    } catch (parseError) {
      console.warn('⚠️ Failed to parse memory extraction JSON:', parseError.message);
      console.warn('Raw response (first 500 chars):', extractedText.substring(0, 500));
      console.warn('Cleaned text attempted:', cleanedText ? cleanedText.substring(0, 200) : 'null');
      
      // Fallback: try to extract basic information heuristically
      extractedFacts = fallbackExtraction(content);
      console.log(`🔄 Fallback extraction yielded ${extractedFacts.length} memories`);
    }

    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ 
      success: true,
      extractedFacts,
      raw: extractedText 
    }));
    
  } catch (err) {
    console.error('❌ Memory extraction error:', err);
    res.statusCode = 500; 
    res.end(JSON.stringify({ error: err.message }));
  }
};

// Fallback extraction using simple heuristics
function fallbackExtraction(content) {
  const facts = [];
  const sentences = content.split(/[.!?]+/).map(s => s.trim()).filter(s => s.length > 20);
  
  for (const sentence of sentences) {
    const lowerSentence = sentence.toLowerCase();
    
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
    
    // Look for preferences
    else if (lowerSentence.includes('i like') || lowerSentence.includes('i prefer') || lowerSentence.includes('i love') || lowerSentence.includes('i hate')) {
      facts.push({
        kind: 'preference',
        text: sentence,
        summary: `User preference: ${sentence.substring(0, 60)}...`,
        importance: 0.7,
        tags: ['preference', 'likes']
      });
    }
    
    // Look for goals or projects
    else if (lowerSentence.includes('project') || lowerSentence.includes('goal') || lowerSentence.includes('working on')) {
      facts.push({
        kind: 'goal',
        text: sentence,
        summary: `User project/goal: ${sentence.substring(0, 60)}...`,
        importance: 0.6,
        tags: ['project', 'goal']
      });
    }
  }
  
  return facts.slice(0, 3); // Limit to 3 fallback extractions
}
