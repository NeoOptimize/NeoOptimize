import os
import logging
from langchain.agents import AgentExecutor, create_react_agent
from langchain.llms import HuggingFacePipeline
from langchain.memory import ConversationSummaryMemory
from langchain.prompts import PromptTemplate
from transformers import pipeline, AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig
import torch

from app.core.tools import tools

logger = logging.getLogger(__name__)

MODEL_NAME = "microsoft/phi-2"
HF_TOKEN = os.getenv("HF_TOKEN")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

def load_llm():
    quantization_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_compute_dtype=torch.float16
    )
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, use_auth_token=HF_TOKEN)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        quantization_config=quantization_config,
        device_map="auto",
        use_auth_token=HF_TOKEN
    )
    pipe = pipeline(
        "text-generation",
        model=model,
        tokenizer=tokenizer,
        max_new_tokens=1024,
        temperature=0.3,
        top_p=0.9,
        repetition_penalty=1.1
    )
    return HuggingFacePipeline(pipeline=pipe)

llm = load_llm()

memory = ConversationSummaryMemory(
    llm=llm,
    memory_key="chat_history",
    return_messages=True,
    max_token_limit=1000
)

prompt = PromptTemplate.from_template("""
Anda adalah Neo AI, asisten cerdas tingkat lanjut yang ahli dalam optimasi, perbaikan, dan manajemen sistem Windows.
Gunakan alat yang tersedia untuk membantu pengguna. Jika tidak yakin, tanyakan informasi lebih lanjut.
Anda memiliki akses ke alat-alat berikut:

{tools}

Gunakan format berikut:
Thought: Anda harus selalu berpikir apa yang harus dilakukan
Action: nama alat yang ingin digunakan, harus salah satu dari [{tool_names}]
Action Input: input untuk alat tersebut dalam format JSON (harus menyertakan "client_id" jika diperlukan)
Observation: hasil dari alat
... (Thought/Action/Action Input/Observation dapat diulang)
Thought: Saya sekarang tahu jawaban akhirnya
Final Answer: jawaban akhir untuk pengguna

Percakapan sebelumnya:
{chat_history}

Pertanyaan baru: {input}
{agent_scratchpad}
""")

agent = create_react_agent(llm=llm, tools=tools, prompt=prompt)
agent_executor = AgentExecutor(
    agent=agent,
    tools=tools,
    memory=memory,
    verbose=True,
    handle_parsing_errors=True,
    max_iterations=5
)