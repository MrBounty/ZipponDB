- [ ] Delete the .new file if an error happend
- [ ] Create a struct that manage the schema

Relationships
- [X] Update the schema Parser and Tokenizer
- [X] Include the name of the link struct with the schema_struct
- [ ] New ConditionValue that is an array of UUID
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

Happy to annonce the v0.2 of my database. New feature include:
- Relationship
- Huge performance increase with multi threading
- Date, time and datetime type
- Linked query
- Compressed binary files
- Logs

All core features of the query language is working, v0.3 will focus on adding things around ot, including:
- Schema migration
- Dump/Bump data
- Recovery
- Better CLI
