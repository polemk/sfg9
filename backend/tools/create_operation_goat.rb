
# Usage: rails runner tools/create_operation_goat.rb

operation = Operation.find_by(key: 'goat')

if operation
  puts "Operation 'goat' already exists!"
  puts "ID: #{operation.id}"
  puts "Title: #{operation.title}"
  puts "Keywords: #{operation.keywords}"
else
  puts "Creating Operation 'goat'..."
  op = Operation.create!(
    key: 'goat',
    title: 'Goat Operation',
    description: 'Operation regarding the Goat functionality',
    keywords: ['goat'].to_json # formatting as JSON string array or just assign array if casted?
    # Model stores it as a string but helper expects array input often?
    # Looking at OperationService: params[:keywords] = ...split
    # Looking at Operation model: keywords is a column.
    # Let's try passing array directly, Rails usually handles JSON columns.
    # If it's a string column mimicking JSON, we need .to_json
  )
  
  # Re-set keywords explicitly to ensure it's saved correctly if validation/casting is tricky
  op.keywords = ['goat'].to_json
  op.save!

  puts "Operation 'goat' created successfully!"
  puts "ID: #{op.id}"
end
