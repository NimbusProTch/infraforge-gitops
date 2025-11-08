#!/usr/bin/env python3
"""
InfraForge Simple API - Demo Application
A lightweight REST API to test the GitOps workflow
"""

import os
import json
import datetime
from flask import Flask, jsonify, request

app = Flask(__name__)

# Configuration from environment
VERSION = os.getenv('APP_VERSION', '1.0.0')
BUILD_ID = os.getenv('BUILD_ID', 'local')
ENV = os.getenv('ENVIRONMENT', 'development')

@app.route('/')
def home():
    """Home endpoint"""
    return jsonify({
        'message': 'Welcome to InfraForge Simple API! 🚀',
        'version': VERSION,
        'build': BUILD_ID,
        'environment': ENV,
        'timestamp': datetime.datetime.utcnow().isoformat()
    })

@app.route('/health')
def health():
    """Health check endpoint for liveness probe"""
    return jsonify({
        'status': 'healthy',
        'version': VERSION,
        'timestamp': datetime.datetime.utcnow().isoformat()
    }), 200

@app.route('/ready')
def ready():
    """Readiness check endpoint"""
    return jsonify({
        'status': 'ready',
        'version': VERSION,
        'timestamp': datetime.datetime.utcnow().isoformat()
    }), 200

@app.route('/version')
def version():
    """Version information"""
    return jsonify({
        'version': VERSION,
        'build_id': BUILD_ID,
        'environment': ENV,
        'python_version': os.sys.version,
        'timestamp': datetime.datetime.utcnow().isoformat()
    })

@app.route('/echo', methods=['POST'])
def echo():
    """Echo endpoint - returns what you send"""
    data = request.get_json() or {}
    return jsonify({
        'echo': data,
        'received_at': datetime.datetime.utcnow().isoformat()
    })

@app.route('/env')
def env():
    """Show environment variables (filtered)"""
    safe_env = {
        k: v for k, v in os.environ.items()
        if not any(secret in k.lower() for secret in ['password', 'secret', 'key', 'token'])
    }
    return jsonify({
        'environment': safe_env,
        'count': len(safe_env)
    })

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'

    print(f"🚀 Starting InfraForge Simple API v{VERSION}")
    print(f"   Build: {BUILD_ID}")
    print(f"   Environment: {ENV}")
    print(f"   Port: {port}")
    print(f"   Debug: {debug}")

    app.run(host='0.0.0.0', port=port, debug=debug)
