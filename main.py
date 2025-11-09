from microdot import Microdot
import random
import os

app = Microdot()

@app.route('/')
async def index(request):
    return f"<p>{random.random():.4f}</p>"

app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080))) #cloud run sets $PORT, default to 8080
