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
    
    let body;
    try {
      body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch (parseError) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ 
        error: 'Invalid JSON',
        message: 'Request body must be valid JSON'
      }));
    }
    
    const { content, userId, sessionId } = body || {};
    
    // Validate required fields
    if (!content || typeof content !== 'string') {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ 
        error: 'Validation Error',
        message: 'content field is required and must be a string'
      }));
    }
    
    if (!userId || typeof userId !== 'string') {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ 
        error: 'Validation Error',
        message: 'userId field is required and must be a string'
      }));
    }
    
    // Validate content length
    if (content.trim().length < 3) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ 
        error: 'Validation Error',
        message: 'content must be at least 3 characters'
      }));
    }
    
    if (content.length > 50000) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ 
        error: 'Validation Error',
        message: 'content exceeds maximum length of 50000 characters'
      }));
    }

    // Create memory extraction prompt with stricter criteria
    const extractionPrompt = `
Extract ONLY significant, memorable facts that meet ALL criteria:

✅ EXTRACT IF:
- Personal identity (name, age, location, family, physical attributes)
- Strong preferences with specifics ("I love coffee" → YES, "that's cool" → NO)
- Professional details (job title, company name, skills, projects with names)
- Education details (college name, university, school name, major, degree) - ALWAYS extract these!
- Explicit instructions ("remember to...", "always...", "never...")
- Goals with specifics ("launching product in Q2", "learning Spanish")
- Relationships with names ("my sister Emma", "my boss John")
- Important dates with context ("birthday is March 15")

❌ NEVER EXTRACT:
- Greetings, acknowledgments, thanks ("hi", "ok", "thanks", "cool", "nice")
- Casual opinions without depth ("that's interesting", "sounds good")
- Temporary states ("I'm tired", "I'm at the store", "just finished lunch")
- Questions or requests without facts ("can you help?", "what do you think?")
- Generic statements without specifics ("I like working", "I enjoy music")
- Confirmations or agreements ("yes", "I agree", "you're right", "exactly")
- Anything under 8 words unless it's a name or explicit nickname

MINIMUM IMPORTANCE THRESHOLDS:
- personal: 0.8 (name, age, location, family)
- preference: 0.65 (must be specific, strong preference)
- professional: 0.65 (job, company, college, university, school, specific skills) - LOWERED to capture education
- goal: 0.65 (must have timeline or specific outcome)
- instruction: 0.75 (explicit directive)
- relationship: 0.7 (must include names)
- event: 0.7 (must have date or clear timeframe)

CONTENT TO ANALYZE:
${content}

EXAMPLES:
Input: "My name is Sarah and I love coffee"
Output: [{"kind":"personal","text":"User's name is Sarah","summary":"Name: Sarah","importance":0.95,"tags":["name","Sarah"]},{"kind":"preference","text":"User loves coffee","summary":"Loves coffee","importance":0.7,"tags":["coffee","drink"]}]

Input: "Call me Alex, I'm working on a SaaS project launching in Q2"
Output: [{"kind":"personal","text":"User prefers to be called Alex","summary":"Nickname: Alex","importance":0.9,"tags":["nickname","Alex"]},{"kind":"goal","text":"User is launching a SaaS project in Q2","summary":"SaaS launch Q2","importance":0.8,"tags":["saas","project","q2","launch"]}]

Input: "My college name is KJSCE" or "I go to MIT" or "I study at Stanford"
Output: [{"kind":"professional","text":"User's college/university is KJSCE","summary":"College: KJSCE","importance":0.85,"tags":["college","kjcse","education"]}]

Input: "Hey, that's cool" or "Thanks" or "Sounds good"
Output: []

Input: "Yes, I agree with that" or "Hmm interesting"
Output: []

Return ONLY valid JSON array (or [] if nothing substantial):
[{"kind":"...","text":"...","summary":"...","importance":0.5-0.95,"tags":[...]}]

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
        
        // Filter and validate each fact with stricter criteria
        extractedFacts = extractedFacts.filter(fact => {
          return fact && 
                 typeof fact.text === 'string' && 
                 typeof fact.summary === 'string' && 
                 typeof fact.importance === 'number' &&
                 fact.text.trim().length >= 10 && // Raised from 6
                 fact.importance >= 0.5; // Raised from 0.2
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

// Stricter fallback extraction - only for very explicit patterns
function fallbackExtraction(content) {
  const trimmed = content.trim();
  if (trimmed.length < 25) return []; // Raised from 15
  
  // Comprehensive trivial pattern check
  const trivialRegex = /^(hi|hello|hey|thanks?|thank you|ok|okay|yes|no|sure|cool|nice|good|great|bye|alright|sounds good|got it|i see|makes sense|interesting|that's (cool|nice|good|great))[.!?]*$/i;
  if (trivialRegex.test(trimmed)) return [];
  
  const facts = [];
  
  // Only extract for VERY EXPLICIT patterns with regex validation
  
  // Name (very strict - must match pattern exactly)
  const nameMatch = content.match(/my name is\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)/i);
  if (nameMatch && nameMatch[1]) {
    facts.push({
      kind: 'personal',
      text: `User's name is ${nameMatch[1]}`,
      summary: `Name: ${nameMatch[1]}`,
      importance: 0.95,
      tags: ['name', nameMatch[1].toLowerCase()]
    });
  }
  
  // Nickname (very explicit only)
  const nicknameMatch = content.match(/(?:call me|nickname is|nickname's)\s+([A-Za-z]{2,15})[,.]?/i);
  if (nicknameMatch && nicknameMatch[1]) {
    facts.push({
      kind: 'personal',
      text: `User prefers to be called ${nicknameMatch[1]}`,
      summary: `Nickname: ${nicknameMatch[1]}`,
      importance: 0.9,
      tags: ['nickname', nicknameMatch[1].toLowerCase()]
    });
  }
  
  // Location (must be specific city/country)
  const locationMatch = content.match(/i (?:live|am) (?:in|from|at)\s+([A-Z][a-z]+(?:,?\s+[A-Z][a-z]+)?)/i);
  if (locationMatch && locationMatch[1] && locationMatch[1].length > 3) {
    facts.push({
      kind: 'personal',
      text: `User lives in ${locationMatch[1]}`,
      summary: `Location: ${locationMatch[1]}`,
      importance: 0.85,
      tags: ['location', locationMatch[1].toLowerCase()]
    });
  }
  
  // Age (must have number)
  const ageMatch = content.match(/(?:i am|i'm)\s+(\d{1,3})\s+years?\s+old/i);
  if (ageMatch && ageMatch[1]) {
    facts.push({
      kind: 'personal',
      text: `User is ${ageMatch[1]} years old`,
      summary: `Age: ${ageMatch[1]}`,
      importance: 0.8,
      tags: ['age', ageMatch[1]]
    });
  }
  
  return facts.slice(0, 2); // Max 2 fallback extractions, only explicit patterns
}
