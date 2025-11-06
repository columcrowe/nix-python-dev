from microdot import Microdot
import random

app = Microdot()

@app.route('/')
async def index(request):
    return f"<p>{random.random():.4f}</p>"

app.run()
