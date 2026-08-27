text = "substituir aplicações antigas"
embedding = Operations::Embeddings::GenerateService.call(text)
if embedding.nil?
  puts "Failed to generate embedding"
  exit
end

nearest = OperationKnowledge.nearest_neighbors(:embedding, embedding, distance: 'cosine').first

if nearest
  puts "Match distance: #{nearest.neighbor_distance} | Operation: #{nearest.operation.key}"
  puts "Knowledge base used for match: #{nearest.content[0..100]}"
else
  puts "No match found at all in DB"
end
