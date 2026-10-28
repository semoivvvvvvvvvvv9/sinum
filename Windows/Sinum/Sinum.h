// Copyright (c) 2025 Project Nova LLC

#pragma once

class FCurlHttpRequest;

namespace Sinum
{
	static bool (*_ProcessRequest)(FCurlHttpRequest*);
	static bool ProcessRequestHook(FCurlHttpRequest* Request);

	void Init();
}