- [ ] Delete the .new file if an error happend
- [ ] Array manipulation
- [ ] Some time keyword like NOW

Relationships
- [X] Update the schema Parser and Tokenizer
- [X] Include the name of the link struct with the schema_struct
- [X] New ConditionValue that is an array of UUID
- [X] When relationship found in filter, check if the type is right and exist
- [X] When parseFilter, get list of UUID as value for relationship
- [X] Add new operation in Filter evalue: IN and !IN
- [~] parseNewData can use filter like in "Add User (friends = [10] {age > 20})" to return UUID
- [ ] parseFilter can use sub filter. "GRAB User {friends IN {age > 20}}" At least one friend in a list of UUID
- [ ] When send, send the entities in link specify between []

Optimizations
- [X] Parse file one time for all conditions, not once per condition
- [X] parse file in parallel, multi threading
  - [X] GRAB
  - [X] DELETE
  - [X] UPDATE
- [ ] Radix Tries ofr UUID list

ADD User (name='Bob', age = 44, best_friend = {id=0000-0000}) => new_user => UPDATE User {id = 0000-0000} TO (best_friend = new_user)

GRAB User [friends] {best_friends IN {name = 'Bob'}}

### Question. How de fuck I am parsing files to get relationships ?
I dont want to parse them more than 3, best 2, perfect 1

The issue is that, I could do optimization here but I dont have enough yet. I need to start doing something that work then I will see.
So I parse:
- All files that 

Now this is where the Radix tree come into place. Because if I get to find one UUID in 50000 files, and I parse all of them, this is meh.
So I need a Radix tree to be able to find all file to parse.

1. Get the list of UUID that need to be parse.
    For example if I do "GRAB User [mom] {name = 'Bob'}". I parse one time the file to get all UUID of User that represent mom; the parse that is already done and need to be done. So if I found 3 Bob's mom UUID
2. Then I create a map of Bob's UUID as keys and a Str as value. The Str is the JSON string of the mom. For that I need to parse the file again and write using additional_data

## Run in WASM for a demo

This could be fun, make a small demo where you get a wasm that run the database locally in the browser.

## How do I return relationship

So lets say I have a query that get 100 comments. And I return Comment.User. That mean once I parsed all Comments and got all UUID of User in ConditionValue in a map.
I need to get all UUID, meaning concatenating all UUID of all ConditionValue into one map. Then I can parse `User` and create a new map with UUID as key and the JSON string as value.
Like that I can iterate as much as I want inside.

That mean:

- If I have a link in AdditionalData to
  - Get all UUID that I need the data (concatenate all maps)
  - Create a new map UUID/JSON object
  - Parse files and populate the new maps

Which also mean that I need to do all of them at the same time at the beguinning. So using AdditionalData, I iterate over all Nodes, find all Links and do what I said above.
I can then save those map into a map with as key the path like `Comment.friends` and value the map that contain UUID/JSON
