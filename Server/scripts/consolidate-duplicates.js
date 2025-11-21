#!/usr/bin/env node

/**
 * One-time script to consolidate duplicate vector_memories
 * Run this AFTER deploying the new dedup code
 * 
 * Usage:
 *   node Server/scripts/consolidate-duplicates.js
 * 
 * This script:
 * 1. Finds memories with identical contentHash
 * 2. Merges them into single memory with combined metadata
 * 3. Deletes duplicates
 * 4. Updates access counts and importance
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
if (!admin.apps.length) {
  try {
    const serviceAccount = require('../../firebase-service-account.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
  } catch (error) {
    console.error('❌ Failed to initialize Firebase Admin');
    console.error('   Make sure firebase-service-account.json exists in project root');
    console.error('   Download from Firebase Console → Project Settings → Service Accounts');
    process.exit(1);
  }
}

const db = admin.firestore();

async function consolidateDuplicates() {
  console.log('🔍 Starting duplicate memory consolidation...\n');
  
  try {
    // Get all vector memories
    const snapshot = await db.collection('vector_memories').get();
    console.log(`📊 Found ${snapshot.size} total memories\n`);
    
    // Group by userId and contentHash
    const groups = {};
    
    snapshot.forEach(doc => {
      const data = doc.data();
      const key = `${data.userId}_${data.contentHash || 'no-hash'}`;
      
      if (!groups[key]) {
        groups[key] = [];
      }
      
      groups[key].push({
        id: doc.id,
        ...data
      });
    });
    
    // Find duplicates
    let duplicateGroups = 0;
    let totalDuplicates = 0;
    let memoriesToDelete = [];
    let memoriesToUpdate = [];
    
    for (const [key, memories] of Object.entries(groups)) {
      if (memories.length > 1 && !key.includes('no-hash')) {
        duplicateGroups++;
        totalDuplicates += memories.length - 1;
        
        console.log(`\n📦 Found ${memories.length} duplicates for hash: ${key.split('_')[1]?.substring(0, 8)}...`);
        
        // Sort by most recent first
        memories.sort((a, b) => {
          const dateA = a.createdAt?.toDate?.() || new Date(0);
          const dateB = b.createdAt?.toDate?.() || new Date(0);
          return dateB - dateA;
        });
        
        // Keep the most recent one, delete others
        const keeper = memories[0];
        const duplicates = memories.slice(1);
        
        console.log(`   ✅ Keeping: "${keeper.summary?.substring(0, 50)}..."`);
        
        // Merge metadata from duplicates
        let combinedImportance = keeper.importance || 0.5;
        let combinedAccessCount = keeper.accessCount || 0;
        let combinedKeywords = new Set(keeper.keywords || []);
        
        duplicates.forEach(dup => {
          console.log(`   ❌ Deleting: "${dup.summary?.substring(0, 50)}..."`);
          combinedImportance = Math.max(combinedImportance, dup.importance || 0.5);
          combinedAccessCount += (dup.accessCount || 0);
          (dup.keywords || []).forEach(kw => combinedKeywords.add(kw));
          memoriesToDelete.push(dup.id);
        });
        
        // Update keeper with merged metadata
        memoriesToUpdate.push({
          id: keeper.id,
          updates: {
            importance: Math.min(1.0, combinedImportance + 0.1),
            accessCount: combinedAccessCount,
            keywords: Array.from(combinedKeywords).slice(0, 20),
            lastAccessedAt: admin.firestore.FieldValue.serverTimestamp()
          }
        });
      }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log(`📊 Consolidation Summary:`);
    console.log(`   • Total duplicate groups: ${duplicateGroups}`);
    console.log(`   • Total duplicates to remove: ${totalDuplicates}`);
    console.log(`   • Memories to update: ${memoriesToUpdate.length}`);
    console.log('='.repeat(60) + '\n');
    
    if (totalDuplicates === 0) {
      console.log('✨ No duplicates found! Database is clean.');
      return;
    }
    
    // Confirm before proceeding
    console.log('⚠️  This will DELETE duplicate memories permanently.');
    console.log('   Press Ctrl+C to cancel, or wait 5 seconds to continue...\n');
    
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    console.log('🔧 Starting cleanup...\n');
    
    // Update keepers
    const batch = db.batch();
    let batchCount = 0;
    
    for (const update of memoriesToUpdate) {
      const ref = db.collection('vector_memories').doc(update.id);
      batch.update(ref, update.updates);
      batchCount++;
      
      // Firestore batch limit is 500
      if (batchCount >= 450) {
        await batch.commit();
        console.log(`✅ Updated ${batchCount} memories`);
        batchCount = 0;
      }
    }
    
    if (batchCount > 0) {
      await batch.commit();
      console.log(`✅ Updated ${batchCount} memories`);
    }
    
    // Delete duplicates
    const deleteBatch = db.batch();
    let deleteCount = 0;
    
    for (const id of memoriesToDelete) {
      const ref = db.collection('vector_memories').doc(id);
      deleteBatch.delete(ref);
      deleteCount++;
      
      if (deleteCount >= 450) {
        await deleteBatch.commit();
        console.log(`🗑️  Deleted ${deleteCount} duplicates`);
        deleteCount = 0;
      }
    }
    
    if (deleteCount > 0) {
      await deleteBatch.commit();
      console.log(`🗑️  Deleted ${deleteCount} duplicates`);
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('✨ Consolidation complete!');
    console.log(`   • Removed ${totalDuplicates} duplicate memories`);
    console.log(`   • Updated ${memoriesToUpdate.length} consolidated memories`);
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error during consolidation:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

// Run the consolidation
consolidateDuplicates()
  .then(() => {
    console.log('\n👋 Done! Exiting...');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Fatal error:', error);
    process.exit(1);
  });

