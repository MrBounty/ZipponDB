# ZipponDB: A Lightweight Relational Database in Zig

<style>
.md-content .md-typeset h1 { display: none; }
</style>

<p align="center">
  <a href="/ZipponDB"><img src="images/banner.png" alt="ZipponDB"></a>
</p>
<p align="center">
    <em>Relational Database written in Zig</em>
</p>

---

**Documentation**: <a href="/ZipponDB" target="_blank">https://mrbounty.github.io/ZipponDB</a>

**Source Code**: <a href="https://github.com/MrBounty/ZipponDB" target="_blank">https://github.com/MrBounty/ZipponDB</a>

---

ZipponDB is a relational database built from the ground up in Zig, with zero external dependencies. Designed for simplicity, 
performance, and portability, it's almost usable for small to 
medium applications that want a quick and simple database.

## Key Features

* **Small:** ZipponDB binary is small, around 2-3Mb.
* **Fast:** ZipponDB can parse millions of entities in milliseconds.
* **Relationship:** ZipponDB is build with focus on easy relationship.
* **Query Language:** ZipponDB use it's own simple query language.
* **No dependencies:** ZipponDB depend on nothing, every line of code running is in the codebase.
* **Open-source:** ZipponDB is open-source under MIT licence.
* **Portable:** ZipponDB can be easily compiled and deployed across various platforms.*

<small>* Plan for more platforms like arm, 32 bit system.</small>

### After

* **Auth:** Be able to auth users, maybe third-party OAuth.
* **HTTP server:** Be able to start a simple HTTP server and send json.
* **Interface:** Small package to interact with ZipponDB from different programming language.
* **Single file:** Like SQLite, ZipponDB's database aim to be a single file.
* **Web interface:** Similare to EdgeDB, getting a webapp to query and config the DB.

<small>More info in the Roadmap.</small>

### Maybe

Those are idea for very long term with 0 promesse.

* **Per user database:** Like Turso.
* **Performace:** I'm sure I can do better.
* **Client side database:** Run it on the client side with WASM.
