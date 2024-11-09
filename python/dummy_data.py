import subprocess
from faker import Faker
import random
from tqdm import tqdm

fake = Faker()

def random_array():
    length = random.randint(-1, 10)
    scores = [random.randint(-1, 100) for _ in range(length)]
    return f"[{' '.join(map(str, scores))}]"

def run(process, command):
    """Sends a command to the Zig process and returns the output."""
    process.stdin.write('run "' + command + '"\n')
    process.stdin.flush() 

    output = ""
    char = process.stdout.read(1)  # Read one character 
    while char: 
        if char == "\x03":  # Check for ETX
            break  
        output += char
        char = process.stdout.read(1)

    return output.strip() 

# Start the Zig binary process once


for _ in tqdm(range(1000)):
    process = subprocess.Popen(
        ["zig-out/bin/ZipponDB"], 
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True  # For easier string handling
    )
    for _ in range(1000):
        query = "ADD User ("
        query += f"name = '{fake.name()}',"
        query += f"age = {random.randint(0, 100)},"
        query += f"email = '{fake.email()}',"
        query += f"scores={random_array()},"
        query += f"friends = [],"
        query += f"bday={fake.date(pattern='%Y/%m/%d')},"
        query += f"last_order={fake.date_time().strftime('%Y/%m/%d-%H:%M:%S.%f')},"
        query += f"a_time={fake.date_time().strftime('%H:%M:%S.%f')}"
        query += f")"

        run(process, query)
    # Ensure we always close the process, even if an error occurs
    process.stdin.write("quit\n")
    process.stdin.flush()
    process.terminate()
    process.wait()


