import subprocess
from faker import Faker
import random
fake = Faker()

# Start the Zig binary process


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

from tqdm import tqdm

for i in tqdm(range(10)):
    process = subprocess.Popen(
        ["zig-out/bin/zippon"], 
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True  # For easier string handling
    )

    query = "ADD User ("
    query += f"name = '{fake.name()}',"
    query += f"age = {random.randint(0, 100)},"
    query += f"email = '{fake.email()}',"
    query += f"scores={random_array()},"
    query += f"friends = [],"
    query += f"bday={fake.date(pattern='%Y/%m/%d')},"
    query += f"last_order={fake.date_time().strftime('%Y/%m/%d-%H:%M:%S.%f')}," # Shouldn't create an error if the millisecond are too long, here it's 6 digit instead of 4
    query += f"a_time={fake.date_time().strftime('%H:%M:%S.%f')}"
    query += f")"

    output = run(process, query)
    print(output)
    process.terminate()

