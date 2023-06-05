# How to create the EXE files for the programming flow

python3 -m venv installer-venv
source installer-venv/bin/activate
pip3 install -r requirements.txt

pyinstaller nrfcredstore/src/nrfcredstore/main.py --collect-submodules application --onefile --name nrfcredstore --path installer-venv/lib/python3.8/site-packages
pyinstaller labelgenerator/generate_label.py --collect-submodules application --onefile --name generate_label --path installer-venv/lib/python3.8/site-packages
