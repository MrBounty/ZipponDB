- [ ] Delete the .new file if an error happend
- [ ] Create a struct that manage the schema

Relationships
- [X] Update the schema Parser and Tokenizer
- [X] Include the name of the link struct with the schema_struct
- [X] New ConditionValue that is an array of UUID
- [ ] When relationship found in filter, check if the type is right and exist
- [ ] When parseFilter, get list of UUID as value for relationship
- [ ] Add new operation in Filter evalue: IN and !IN
- [ ] parseNewData can use filter like in "Add User (friends = [10] {age > 20})" to return UUID
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

### Radix tree

Ok so new problem. Given a list of UUID, I need a way to find all file index to parse.
And even better if I can get the number of UUID per files, so I can stop parsing them early.

Happy to annonce the v0.2 of my database. New feature include:
- Relationship
- Huge performance increase with multi threading
- Date, time and datetime type
- Compressed binary files
- Logs

All core features of the query language, exept linked queries, is working, v0.3 will focus on adding things around it, including:
- Schema migration
- Dump/Bump data
- Recovery
- Better CLI

Query optimization for later:
- If a filter use id to find something, to stop after find it, as I know there is no other struct with the same id
